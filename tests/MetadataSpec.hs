{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}

module MetadataSpec (spec) where

import Crypto.WebAuthn.Metadata (metadataBlobToRegistry)
import Crypto.WebAuthn.Metadata.Service.Processing (RootCertificate (RootCertificate), fidoAllianceRootCertificate, jsonToPayload, jwtToJson)
import Crypto.WebAuthn.Metadata.Service.WebIDL (MetadataBLOBPayload, entries, legalHeader, nextUpdate, no)
import Data.Aeson (Result (Success), ToJSON (toJSON), decodeFileStrict, fromJSON)
import Data.Aeson.Types (Result (Error))
import qualified Data.ByteString as BS
import Data.Either (isRight)
import Data.HashMap.Strict ((!), (!?))
import Data.List (intercalate)
import qualified Data.PEM as PEM
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import Data.These (These (That, These, This))
import qualified Data.X509 as X509
import qualified Data.X509.CertificateStore as X509
import Spec.Util (predeterminedDateTime)
import Test.Hspec (SpecWith, describe, it, shouldBe, shouldSatisfy)
import Test.Hspec.Expectations.Json (shouldBeUnorderedJson)

golden :: FilePath -> SpecWith ()
golden subdir = describe subdir $ do
  it "can verify and extract the blob payload" $ do
    origin <- Text.unpack . Text.strip . decodeUtf8 <$> BS.readFile ("tests/golden-metadata/" <> subdir <> "/origin")

    certBytes <- BS.readFile $ "tests/golden-metadata/" <> subdir <> "/root.crt"
    let Right [PEM.pemContent -> pem] = PEM.pemParseBS certBytes
        Right cert = X509.decodeSignedCertificate pem
        store = X509.makeCertificateStore [cert]

    blobBytes <- BS.readFile $ "tests/golden-metadata/" <> subdir <> "/blob.jwt"
    let Right result = jwtToJson blobBytes (RootCertificate store origin) predeterminedDateTime

    Just expectedPayload <- decodeFileStrict $ "tests/golden-metadata/" <> subdir <> "/payload.json"

    (result !? "legalHeader") `shouldBe` toJSON <$> legalHeader expectedPayload
    (result !? "no") `shouldBe` Just (toJSON (no expectedPayload))
    (result !? "nextUpdate") `shouldBe` Just (toJSON (nextUpdate expectedPayload))
    (result ! "entries") `shouldBeUnorderedJson` toJSON (entries expectedPayload)

  it "can decode and reencode the payload to the partially parsed JSON" $ do
    Just payload <- decodeFileStrict $ "tests/golden-metadata/" <> subdir <> "/payload.json"
    case fromJSON payload of
      Error err -> fail err
      Success (value :: MetadataBLOBPayload) ->
        toJSON value `shouldBeUnorderedJson` payload

  it "can decode and reencode the payload to the partially parsed JSON" $ do
    Just value <- decodeFileStrict $ "tests/golden-metadata/" <> subdir <> "/payload.json"
    case jsonToPayload value of
      This err -> fail $ show err
      These err _result -> fail $ show err
      That _result -> pure ()

spec :: SpecWith ()
spec = do
  describe "Golden" $ do
    golden "small"
    golden "big"
  describe "fidoAllianceRootCertificate" $ do
    it "can validate the payload" $ do
      blobBytes <- BS.readFile "tests/golden-metadata/big/blob.jwt"
      jwtToJson blobBytes fidoAllianceRootCertificate predeterminedDateTime `shouldSatisfy` isRight
  describe "MDS with errors" $ do
    it "can process an MDS file with errors" $ do
      blobBytes <- BS.readFile "tests/golden-metadata/big/blob-with-errors.jwt"
      case metadataBlobToRegistry blobBytes predeterminedDateTime of
        Right (This err) -> error $ intercalate "," (Text.unpack <$> err)
        Right (That _res) -> error "Expected parsing errors as well as registry"
        Right (These _errs _res) -> pure ()
        Left err -> error $ Text.unpack err
