{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Crypto.Fido2.Model.Binary.Encoding
  ( -- * Encoding raw fields
    encodeRawPublicKeyCredential,
    encodeRawAuthenticatorData,
    encodeRawCollectedClientData,

    -- * Encoding structures to bytes
    encodeAttestationObject,
    encodeCollectedClientData,
  )
where

import qualified Codec.CBOR.Term as CBOR
import qualified Codec.CBOR.Write as CBOR
import qualified Codec.Serialise as CBOR
import qualified Crypto.Fido2.Model as M
import Crypto.Fido2.Model.WebauthnType (SWebauthnType (SCreate, SGet), SingI, sing)
import Crypto.Fido2.PublicKey (encodePublicKey)
import qualified Data.Aeson as Aeson
import qualified Data.Binary.Put as Binary
import Data.Bits ((.|.))
import qualified Data.Bits as Bits
import Data.ByteArray (convert)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64.URL as Base64Url
import Data.ByteString.Builder (Builder, stringUtf8, toLazyByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import qualified Data.UUID as UUID
import Data.Word (Word16, Word8)

-- | Encodes all raw fields of a 'M.PublicKeyCredential'. This function is
-- mainly useful for testing that the encoding/decoding functions are correct.
-- The counterpart to this function is 'Crypto.Fido2.Model.Binary.Decoding.stripRawPublicKeyCredential'
encodeRawPublicKeyCredential :: forall t raw. SingI t => M.PublicKeyCredential t raw -> M.PublicKeyCredential t 'True
encodeRawPublicKeyCredential M.PublicKeyCredential {..} =
  M.PublicKeyCredential
    { pkcResponse = case sing @t of
        SCreate -> encodeRawAuthenticatorAttestationResponse pkcResponse
        SGet -> encodeRawAuthenticatorAssertionResponse pkcResponse,
      ..
    }
  where
    encodeRawAuthenticatorAssertionResponse :: M.AuthenticatorResponse 'M.Get raw -> M.AuthenticatorResponse 'M.Get 'True
    encodeRawAuthenticatorAssertionResponse M.AuthenticatorAssertionResponse {..} =
      M.AuthenticatorAssertionResponse
        { argClientData = encodeRawCollectedClientData argClientData,
          argAuthenticatorData = encodeRawAuthenticatorData argAuthenticatorData,
          ..
        }

    encodeRawAuthenticatorAttestationResponse :: M.AuthenticatorResponse 'M.Create raw -> M.AuthenticatorResponse 'M.Create 'True
    encodeRawAuthenticatorAttestationResponse M.AuthenticatorAttestationResponse {..} =
      M.AuthenticatorAttestationResponse
        { arcClientData = encodeRawCollectedClientData arcClientData,
          arcAttestationObject = encodeRawAttestationObject arcAttestationObject,
          ..
        }

    encodeRawAttestationObject :: M.AttestationObject raw -> M.AttestationObject 'True
    encodeRawAttestationObject M.AttestationObject {..} =
      M.AttestationObject
        { aoAuthData = encodeRawAuthenticatorData aoAuthData,
          ..
        }

-- | Encodes all raw fields of a 'M.AuthenticatorData'. This function is needed
-- for an authenticator implementation
encodeRawAuthenticatorData :: forall t raw. SingI t => M.AuthenticatorData t raw -> M.AuthenticatorData t 'True
encodeRawAuthenticatorData M.AuthenticatorData {..} =
  M.AuthenticatorData
    { adRawData = M.WithRaw bytes,
      adAttestedCredentialData = rawAttestedCredentialData,
      ..
    }
  where
    rawAttestedCredentialData = encodeRawAttestedCredentialData adAttestedCredentialData

    bytes :: BS.ByteString
    bytes = LBS.toStrict $ toLazyByteString builder

    -- https://www.w3.org/TR/webauthn-2/#flags
    flags :: Word8
    flags =
      userPresentFlag
        .|. userVerifiedFlag
        .|. attestedCredentialDataPresentFlag
        .|. extensionsPresentFlag
      where
        userPresentFlag = if M.adfUserPresent adFlags then Bits.bit 0 else 0
        userVerifiedFlag = if M.adfUserVerified adFlags then Bits.bit 2 else 0
        attestedCredentialDataPresentFlag = case sing @t of
          SCreate -> Bits.bit 6
          SGet -> 0
        extensionsPresentFlag = case adExtensions of
          Just _ -> Bits.bit 7
          Nothing -> 0

    -- https://www.w3.org/TR/webauthn-2/#sctn-authenticator-data
    builder :: Builder
    builder =
      Binary.execPut (Binary.putByteString $ convert $ M.unRpIdHash adRpIdHash)
        <> Binary.execPut (Binary.putWord8 flags)
        <> Binary.execPut (Binary.putWord32be $ M.unSignatureCounter adSignCount)
        <> ( case sing @t of
               SCreate -> encodeAttestedCredentialData rawAttestedCredentialData
               SGet -> mempty
           )
        <> maybe mempty encodeExtensions adExtensions

    encodeExtensions :: M.AuthenticatorExtensionOutputs -> Builder
    encodeExtensions M.AuthenticatorExtensionOutputs {} = CBOR.toBuilder $ CBOR.encode entries
      where
        entries :: HashMap Text CBOR.Term
        entries = HashMap.empty

    -- https://www.w3.org/TR/webauthn-2/#sctn-attested-credential-data
    encodeAttestedCredentialData :: M.AttestedCredentialData 'M.Create 'True -> Builder
    encodeAttestedCredentialData M.AttestedCredentialData {..} =
      Binary.execPut (Binary.putLazyByteString $ UUID.toByteString $ M.unAAGUID acdAaguid)
        <> Binary.execPut (Binary.putWord16be credentialLength)
        <> Binary.execPut (Binary.putByteString $ M.unCredentialId acdCredentialId)
        <> Binary.execPut (Binary.putByteString $ M.unRaw acdCredentialPublicKeyBytes)
      where
        credentialLength :: Word16
        credentialLength = fromIntegral $ BS.length $ M.unCredentialId acdCredentialId

    encodeRawAttestedCredentialData :: forall t raw. SingI t => M.AttestedCredentialData t raw -> M.AttestedCredentialData t 'True
    encodeRawAttestedCredentialData = case sing @t of
      SCreate -> \M.AttestedCredentialData {..} ->
        M.AttestedCredentialData
          { acdCredentialPublicKeyBytes =
              M.WithRaw $ LBS.toStrict $ CBOR.toLazyByteString $ encodePublicKey acdCredentialPublicKey,
            ..
          }
      SGet -> \M.NoAttestedCredentialData -> M.NoAttestedCredentialData

-- | Encodes all raw fields of a 'M.CollectedClientData'. This function is
-- needed for a client implementation
encodeRawCollectedClientData :: forall t raw. SingI t => M.CollectedClientData t raw -> M.CollectedClientData t 'True
encodeRawCollectedClientData M.CollectedClientData {..} = M.CollectedClientData {..}
  where
    ccdRawData = M.WithRaw $ LBS.toStrict $ toLazyByteString builder

    -- https://www.w3.org/TR/webauthn-2/#clientdatajson-serialization
    builder :: Builder
    builder =
      stringUtf8 "{\"type\":"
        <> jsonBuilder typeValue
        <> stringUtf8 ",\"challenge\":"
        <> jsonBuilder challengeValue
        <> stringUtf8 ",\"origin\":"
        <> jsonBuilder originValue
        <> stringUtf8 ",\"crossOrigin\":"
        <> jsonBuilder crossOriginValue
        <> stringUtf8 "}"

    typeValue :: Text
    typeValue = case sing @t of
      SCreate -> "webauthn.create"
      SGet -> "webauthn.get"

    challengeValue :: Text
    challengeValue = decodeUtf8 (Base64Url.encode (M.unChallenge ccdChallenge))

    originValue :: Text
    originValue = M.unOrigin ccdOrigin

    crossOriginValue :: Bool
    crossOriginValue = ccdCrossOrigin

    jsonBuilder :: Aeson.ToJSON a => a -> Builder
    jsonBuilder = Aeson.fromEncoding . Aeson.toEncoding

-- | Encodes an 'M.AttestationObject' as a 'BS.ByteString'. This is needed by
-- the client side to generate a valid JSON response
encodeAttestationObject :: M.AttestationObject 'True -> BS.ByteString
encodeAttestationObject M.AttestationObject {..} = CBOR.toStrictByteString $ CBOR.encodeTerm term
  where
    -- https://www.w3.org/TR/webauthn-2/#sctn-generating-an-attestation-object
    term :: CBOR.Term
    term =
      CBOR.TMap
        [ (CBOR.TString "authData", CBOR.TBytes $ M.unRaw $ M.adRawData aoAuthData),
          (CBOR.TString "fmt", CBOR.TString $ M.asfIdentifier aoFmt),
          (CBOR.TString "attStmt", M.asfEncode aoFmt aoAttStmt)
        ]

-- | Encodes an 'M.CollectedClientData' as a 'BS.ByteString'. This is needed by
-- the client side to generate a valid JSON response
encodeCollectedClientData :: forall t. SingI t => M.CollectedClientData t 'True -> BS.ByteString
encodeCollectedClientData M.CollectedClientData {..} = M.unRaw ccdRawData
