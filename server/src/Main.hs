{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ViewPatterns #-}

module Main
  ( main,
  )
where

import Control.Monad (when)
import Control.Monad.Except (runExceptT)
import Control.Monad.Trans (lift)
import Control.Monad.Trans.Maybe (MaybeT (MaybeT, runMaybeT))
import Crypto.Fido2.Metadata.Service.Processing (RootCertificate (RootCertificate), createMetadataRegistry, getPayload)
import qualified Crypto.Fido2.Model as M
import qualified Crypto.Fido2.Model.Binary.Decoding as MD
import qualified Crypto.Fido2.Model.JavaScript as JS
import Crypto.Fido2.Model.JavaScript.Decoding (decodeCreatedPublicKeyCredential, decodeRequestedPublicKeyCredential)
import Crypto.Fido2.Model.JavaScript.Encoding (encodePublicKeyCredentialCreationOptions, encodePublicKeyCredentialRequestOptions)
import Crypto.Fido2.Operations.Assertion (verifyAssertionResponse)
import Crypto.Fido2.Operations.Attestation (AttestationError, AttestationResult (rEntry), allSupportedFormats, verifyAttestationResponse)
import Crypto.Fido2.Operations.Common (CredentialEntry (CredentialEntry, ceCredentialId, ceUserHandle))
import Crypto.Fido2.PublicKey (COSEAlgorithmIdentifier (COSEAlgorithmIdentifierES256))
import Crypto.Hash (hash)
import Data.Aeson (FromJSON, Value (String))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64.URL as Base64
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.PEM as PEM
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Text.IO as Text
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Lazy.Encoding as LText
import Data.Validation (Validation (Failure, Success))
import qualified Data.X509 as X509
import qualified Database
import GHC.Generics (Generic)
import qualified Network.HTTP.Types as HTTP
import Network.Wai.Middleware.Static (addBase, staticPolicy)
import PendingOps (PendingOps, defaultPendingOpsConfig, getPendingOptions, insertPendingOptions, newPendingOps)
import System.Environment (getArgs)
import System.Hourglass (dateCurrent)
import System.Random.Stateful (globalStdGen, uniformM)
import qualified Web.Cookie as Cookie
import Web.Scotty (ScottyM)
import qualified Web.Scotty as Scotty

data RegisterBeginReq = RegisterBeginReq
  { accountName :: Text,
    accountDisplayName :: Text
  }
  deriving (Show, FromJSON)
  deriving stock (Generic)

setAuthenticatedAs :: Database.Connection -> M.UserHandle -> Scotty.ActionM ()
setAuthenticatedAs db userHandle = do
  token <- Scotty.liftAndCatchIO $ uniformM globalStdGen
  Scotty.liftAndCatchIO $
    Database.withTransaction db $ \tx ->
      Database.insertAuthToken tx token userHandle
  setAuthToken token

setAuthToken :: Database.AuthToken -> Scotty.ActionM ()
setAuthToken token = do
  let setCookie =
        Cookie.defaultSetCookie
          { Cookie.setCookieName = "auth-token",
            Cookie.setCookieValue = Base64.encodeUnpadded (Database.unAuthToken token),
            Cookie.setCookieSameSite = Just Cookie.sameSiteStrict,
            Cookie.setCookieHttpOnly = True,
            Cookie.setCookiePath = Just "/",
            Cookie.setCookieSecure = True,
            -- Keep user logged in for an hour
            Cookie.setCookieMaxAge = Just (60 * 60 * 24)
          }
  Scotty.setHeader
    "Set-Cookie"
    (LText.decodeUtf8 (Builder.toLazyByteString (Cookie.renderSetCookie setCookie)))

getAuthToken :: MaybeT Scotty.ActionM Database.AuthToken
getAuthToken = do
  cookieHeader <- MaybeT $ Scotty.header "cookie"
  let cookies = Cookie.parseCookies $ LBS.toStrict $ LText.encodeUtf8 cookieHeader
  sessionCookie <- MaybeT . pure $ lookup "auth-token" cookies
  MaybeT . pure $ either (const Nothing) (Just . Database.AuthToken) $ Base64.decodeUnpadded sessionCookie

getAuthenticatedUser :: Database.Connection -> Scotty.ActionM (Maybe M.UserAccountName)
getAuthenticatedUser db = runMaybeT $ do
  token <- getAuthToken
  user <- MaybeT $
    Scotty.liftAndCatchIO $
      Database.withTransaction db $ \tx ->
        Database.queryUserByAuthToken tx token
  lift $ setAuthToken token
  pure user

logout :: Database.Connection -> Scotty.ActionM ()
logout db = do
  runMaybeT getAuthToken >>= \case
    Nothing -> pure ()
    Just token -> do
      Scotty.liftAndCatchIO $
        Database.withTransaction db $ \tx ->
          Database.deleteAuthToken tx token

  let setCookie =
        Cookie.defaultSetCookie
          { Cookie.setCookieName = "auth-token",
            Cookie.setCookieValue = "",
            Cookie.setCookieSameSite = Just Cookie.sameSiteStrict,
            Cookie.setCookieSecure = True,
            Cookie.setCookieHttpOnly = True,
            Cookie.setCookiePath = Just "/",
            Cookie.setCookieMaxAge = Just 0
          }
  Scotty.setHeader
    "Set-Cookie"
    (LText.decodeUtf8 (Builder.toLazyByteString (Cookie.renderSetCookie setCookie)))

app :: M.Origin -> M.RpIdHash -> Database.Connection -> PendingOps -> ScottyM ()
app origin rpIdHash db pending = do
  Scotty.middleware (staticPolicy (addBase "dist"))
  Scotty.get "/" $ do
    getAuthenticatedUser db >>= \case
      Nothing -> Scotty.redirect "unauthenticated.html"
      Just _ -> Scotty.redirect "authenticated.html"
  Scotty.post "/register/begin" $ beginRegistration db pending
  Scotty.post "/register/complete" $ completeRegistration origin rpIdHash db pending
  Scotty.post "/login/begin" $ beginLogin db pending
  Scotty.post "/login/complete" $ completeLogin origin rpIdHash db pending
  Scotty.get "/requires-auth" $ do
    getAuthenticatedUser db >>= \case
      Nothing -> Scotty.raiseStatus HTTP.status401 "Please authenticate first"
      Just name -> Scotty.json $ String $ M.unUserAccountName name
  Scotty.get "/logout" $ logout db

mkCredentialDescriptor :: CredentialEntry -> M.PublicKeyCredentialDescriptor
mkCredentialDescriptor CredentialEntry {ceCredentialId} =
  M.PublicKeyCredentialDescriptor
    { M.pkcdTyp = M.PublicKeyCredentialTypePublicKey,
      M.pkcdId = ceCredentialId,
      M.pkcdTransports = Nothing
    }

data RegistrationResult
  = RegistrationSuccess
  | AlreadyRegistered
  | AttestationError AttestationError
  deriving (Show)

handleError :: Show e => Either e a -> Scotty.ActionM a
handleError (Left x) = Scotty.raiseStatus HTTP.status400 . LText.fromStrict . Text.pack . show $ x
handleError (Right x) = pure x

beginLogin :: Database.Connection -> PendingOps -> Scotty.ActionM ()
beginLogin db pending = do
  accountName <- M.UserAccountName <$> Scotty.jsonData @Text
  credentials <- Scotty.liftAndCatchIO $
    Database.withTransaction db $ \tx -> do
      Database.queryCredentialEntriesByUser tx accountName
  when (null credentials) $ Scotty.raiseStatus HTTP.status404 "User not found"
  options <- Scotty.liftAndCatchIO $
    insertPendingOptions pending $ \challenge -> do
      M.PublicKeyCredentialRequestOptions
        { M.pkcogRpId = Nothing,
          M.pkcogTimeout = Nothing,
          M.pkcogChallenge = challenge,
          M.pkcogAllowCredentials = map mkCredentialDescriptor credentials,
          M.pkcogUserVerification = M.UserVerificationRequirementPreferred,
          M.pkcogExtensions = Nothing
        }

  Scotty.json $ encodePublicKeyCredentialRequestOptions options

completeLogin :: M.Origin -> M.RpIdHash -> Database.Connection -> PendingOps -> Scotty.ActionM ()
completeLogin origin rpIdHash db pending = do
  credential <- Scotty.jsonData @JS.RequestedPublicKeyCredential

  cred <- case decodeRequestedPublicKeyCredential credential of
    Left err -> fail $ show err
    Right result -> pure result
  Scotty.liftAndCatchIO $ putStrLn $ "/login/complete, received " <> show (MD.stripRawPublicKeyCredential cred)

  options <-
    Scotty.liftAndCatchIO (getPendingOptions pending cred) >>= \case
      Left err -> Scotty.raiseStatus HTTP.status401 $ "Challenge error: " <> LText.pack err
      Right result -> pure result

  mentry <- Scotty.liftAndCatchIO $
    Database.withTransaction db $ \tx ->
      Database.queryCredentialEntryByCredential tx (M.pkcIdentifier cred)
  entry <- case mentry of
    Nothing -> fail "Credential not found"
    Just entry -> pure entry

  _newSigCount <- case verifyAssertionResponse origin rpIdHash (Just (ceUserHandle entry)) entry options cred of
    Failure (err :| _) -> fail $ show err
    Success result -> pure result
  -- FIXME: Update signature count in database
  setAuthenticatedAs db (ceUserHandle entry)
  Scotty.json $ String "success"

beginRegistration :: Database.Connection -> PendingOps -> Scotty.ActionM ()
beginRegistration db pending = do
  req@RegisterBeginReq {accountName, accountDisplayName} <- Scotty.jsonData @RegisterBeginReq
  Scotty.liftAndCatchIO $ putStrLn $ "/register/begin, received " <> show req
  exists <- Scotty.liftAndCatchIO $
    Database.withTransaction db $ \tx -> do
      Database.userExists tx (M.UserAccountName accountName)
  when exists $ Scotty.raiseStatus HTTP.status409 "Account name already taken"
  userId <- Scotty.liftAndCatchIO $ uniformM globalStdGen
  let user =
        M.PublicKeyCredentialUserEntity
          { M.pkcueId = userId,
            M.pkcueDisplayName = M.UserAccountDisplayName accountDisplayName,
            M.pkcueName = M.UserAccountName accountName
          }
  options <- Scotty.liftAndCatchIO $ insertPendingOptions pending $ defaultPkcco user
  Scotty.liftAndCatchIO $ putStrLn $ "/register/begin, sending " <> show options
  Scotty.json $ encodePublicKeyCredentialCreationOptions options

completeRegistration :: M.Origin -> M.RpIdHash -> Database.Connection -> PendingOps -> Scotty.ActionM ()
completeRegistration origin rpIdHash db pending = do
  credential <- Scotty.jsonData @JS.CreatedPublicKeyCredential
  cred <- case decodeCreatedPublicKeyCredential allSupportedFormats credential of
    Left err -> fail $ show err
    Right result -> pure result
  Scotty.liftAndCatchIO $ putStrLn $ "/register/complete, received " <> show (MD.stripRawPublicKeyCredential cred)

  options <-
    Scotty.liftAndCatchIO (getPendingOptions pending cred) >>= \case
      Left err -> Scotty.raiseStatus HTTP.status401 $ "Challenge error: " <> LText.pack err
      Right result -> pure result

  let userHandle = M.pkcueId $ M.pkcocUser options
  now <- Scotty.liftAndCatchIO dateCurrent
  bytes <- Scotty.liftAndCatchIO $ LBS.readFile "../tests/golden-metadata/big/blob.jwt"
  certBytes <- Scotty.liftAndCatchIO $ BS.readFile "../tests/golden-metadata/big/root.crt"
  let Right [PEM.pemContent -> pem] = PEM.pemParseBS certBytes
      Right cert = X509.decodeSignedCertificate pem
  epay <- Scotty.liftAndCatchIO $ runExceptT $ getPayload bytes (RootCertificate cert "mds.fidoalliance.org")
  payload <- case epay of
    Left err -> Scotty.raiseStatus HTTP.status401 (LText.pack $ show err)
    Right result -> return result
  let registry = createMetadataRegistry payload
  -- step 1 to 17
  -- We abort if we couldn't attest the credential
  -- FIXME
  entry <- case verifyAttestationResponse origin rpIdHash registry now options cred of
    Failure (err :| _) -> fail $ show err
    Success result -> do
      Scotty.liftAndCatchIO $ print result
      pure $ rEntry result
  -- if the credential was succesfully attested, we will see if the
  -- credential doesn't exist yet, and if it doesn't, insert it.
  result <- Scotty.liftAndCatchIO $
    Database.withTransaction db $ \tx -> do
      -- If a credential with this id existed already, it must belong to the
      -- current user, otherwise it's an error. The spec allows removing the
      -- credential from the old user instead, but we don't do that.
      mexistingEntry <- Database.queryCredentialEntryByCredential tx (ceCredentialId entry)
      case mexistingEntry of
        Nothing -> do
          Database.insertUser tx $ M.pkcocUser options
          Database.insertCredentialEntry tx entry
          pure $ Right ()
        Just existingEntry | userHandle == ceUserHandle existingEntry -> pure $ Right ()
        Just _differentUserId -> pure $ Left AlreadyRegistered
  handleError result
  setAuthenticatedAs db userHandle
  Scotty.json $ String "success"

defaultPkcco :: M.PublicKeyCredentialUserEntity -> M.Challenge -> M.PublicKeyCredentialOptions 'M.Create
defaultPkcco userEntity challenge =
  M.PublicKeyCredentialCreationOptions
    { M.pkcocRp = M.PublicKeyCredentialRpEntity {M.pkcreId = Nothing, M.pkcreName = "ACME"},
      M.pkcocUser = userEntity,
      M.pkcocChallenge = challenge,
      -- Empty credentialparameters are not supported.
      M.pkcocPubKeyCredParams =
        [ M.PublicKeyCredentialParameters
            { M.pkcpTyp = M.PublicKeyCredentialTypePublicKey,
              M.pkcpAlg = COSEAlgorithmIdentifierES256
            }
        ],
      M.pkcocTimeout = Nothing,
      M.pkcocExcludeCredentials = [],
      M.pkcocAuthenticatorSelection =
        Just
          M.AuthenticatorSelectionCriteria
            { M.ascAuthenticatorAttachment = Nothing,
              M.ascResidentKey = M.ResidentKeyRequirementDiscouraged,
              M.ascUserVerification = M.UserVerificationRequirementPreferred
            },
      M.pkcocAttestation = M.AttestationConveyancePreferenceDirect,
      M.pkcocExtensions = Nothing
    }

main :: IO ()
main = do
  [Text.pack -> origin, Text.pack -> domain, read -> port] <- getArgs
  db <- Database.connect
  Database.initialize db
  pending <- newPendingOps defaultPendingOpsConfig
  Text.putStrLn $ "You can view the web-app at: " <> origin
  let rpIdHash = M.RpIdHash $ hash $ Text.encodeUtf8 domain
  Scotty.scotty port $ app (M.Origin origin) rpIdHash db pending
