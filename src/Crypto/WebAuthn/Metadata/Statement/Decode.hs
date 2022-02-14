{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RecordWildCards #-}

-- | Stability: experimental
-- This module contains functions to further decode
-- [FIDO Metadata Statement](https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.0-ps-20210518.html)
-- IDL types defined in 'Crypto.WebAuthn.Metadata.Statement.IDL' into the Haskell-specific types defined in 'Crypto.WebAuthn.Metadata.Statement.Types'
module Crypto.WebAuthn.Metadata.Statement.Decode
  ( decodeMetadataStatement,
    decodeAAGUID,
    decodeSubjectKeyIdentifier,
    decodeCertificate,
  )
where

import Control.Monad (unless)
import Crypto.Hash (SHA1, digestFromByteString)
import qualified Crypto.WebAuthn.Metadata.FidoRegistry as Registry
import Crypto.WebAuthn.Metadata.Statement.Types (WebauthnAttestationType (WebauthnAttestationAttCA, WebauthnAttestationBasic))
import qualified Crypto.WebAuthn.Metadata.Statement.Types as StatementTypes
import qualified Crypto.WebAuthn.Metadata.Statement.WebIDL as StatementIDL
import qualified Crypto.WebAuthn.Metadata.WebIDL as IDL
import qualified Crypto.WebAuthn.Model as M
import Crypto.WebAuthn.Model.Identifier (AAGUID (AAGUID), AuthenticatorIdentifier (AuthenticatorIdentifierFido2, AuthenticatorIdentifierFidoU2F), SubjectKeyIdentifier (SubjectKeyIdentifier))
import Data.Bifunctor (first)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Base64 as Base64
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import qualified Data.UUID as UUID
import qualified Data.X509 as X509

-- | Decodes an 'M.AAGUID' from an [aaguid](https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.0-ps-20210518.html#dom-metadatastatement-aaguid) field of a metadata statement or an [aaguid](https://fidoalliance.org/specs/mds/fido-metadata-service-v3.0-ps-20210518.html#dom-metadatablobpayloadentry-aaguid) field of a metadata service payload entry field
decodeAAGUID :: StatementIDL.AAGUID -> Either Text (AuthenticatorIdentifier 'M.Fido2)
decodeAAGUID (StatementIDL.AAGUID aaguidText) = case UUID.fromText aaguidText of
  Nothing -> Left $ "Could not decode metadata aaguid: " <> aaguidText
  Just aaguid -> Right $ AuthenticatorIdentifierFido2 $ AAGUID aaguid

-- | Decodes a 'M.SubjectKeyIdentifier' from an [attestationCertificateKeyIdentifiers](https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.0-ps-20210518.html#dom-metadatastatement-attestationcertificatekeyidentifiers) field of a metadata statement or an [attestationCertificateKeyIdentifiers](https://fidoalliance.org/specs/mds/fido-metadata-service-v3.0-ps-20210518.html#dom-metadatablobpayloadentry-attestationcertificatekeyidentifiers) field of a metadata service payload entry
decodeSubjectKeyIdentifier :: IDL.DOMString -> Either Text (AuthenticatorIdentifier 'M.FidoU2F)
decodeSubjectKeyIdentifier subjectKeyIdentifierText = case Base16.decode (encodeUtf8 subjectKeyIdentifierText) of
  Left err -> Left $ "A attestationCertificateKeyIdentifier failed to parse because it's not a valid base-16 encoding: " <> subjectKeyIdentifierText <> ", error: " <> Text.pack err
  Right bytes -> case digestFromByteString @SHA1 bytes of
    Nothing -> Left $ "A attestationCertificateKeyIdentifier failed to parse because it has the wrong length for a SHA1 hash: " <> subjectKeyIdentifierText
    Just hash -> Right $ AuthenticatorIdentifierFidoU2F $ SubjectKeyIdentifier hash

-- | Decodes a 'X509.SignedCertificate' from an [attestationRootCertificates](https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.0-ps-20210518.html#dom-metadatastatement-attestationrootcertificates) field of a metadata statement or the [certificate](https://fidoalliance.org/specs/mds/fido-metadata-service-v3.0-ps-20210518.html#dom-statusreport-certificate) field of a metadata service status report
decodeCertificate :: IDL.DOMString -> Either Text X509.SignedCertificate
decodeCertificate text =
  -- TODO: Remove Text.strip, it's only needed because of a spec violation, see
  -- <https://github.com/tweag/haskell-fido2/issues/68>
  -- TODO: Don't use decodeLenient, it's only needed because of a spec
  -- violation, see TODO above
  let bytes = Base64.decodeLenient (encodeUtf8 $ Text.strip text)
   in case X509.decodeSignedCertificate bytes of
        Left err -> Left $ "A certificate failed to parse because it's not a valid encoding: " <> text <> ", error: " <> Text.pack err
        Right certificate -> Right certificate

-- | Fully decodes a [MetadataStatement](https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.0-ps-20210518.html#metadata-keys).
-- The @p@ type parameter is the 'StatementIDL.ProtocolFamily' that this metadata statement is for.
decodeMetadataStatement ::
  -- | The raw metadata statement, directly parsed from JSON
  StatementIDL.MetadataStatement ->
  -- | Either an early exit with 'Left', where @Left Nothing@ signals that
  -- this entry can be skipped because it's not relevant for Webauthn, and
  -- @Left . Just@ signals that an error happened during decoding
  -- Otherwise a successful result with 'Right'
  Either (Maybe Text) StatementTypes.MetadataStatement
decodeMetadataStatement StatementIDL.MetadataStatement {..} = do
  let msLegalHeader = legalHeader
      msDescription = description
      msAlternativeDescriptions = alternativeDescriptions
      msAuthenticatorVersion = authenticatorVersion
  unless (schema == 3) $ Left $ Just $ "Schema version is not 3 but " <> Text.pack (show schema)
  let msUpv = upv
      msAuthenticationAlgorithms = authenticationAlgorithms
      msPublicKeyAlgAndEncodings = publicKeyAlgAndEncodings
  msAttestationTypes <- decodeAttestationTypes attestationTypes
  let msUserVerificationDetails = userVerificationDetails
      msKeyProtection = keyProtection
      msIsKeyRestricted = isKeyRestricted
      msIsFreshUserVerificationRequired = isFreshUserVerificationRequired
      msMatcherProtection = matcherProtection
      msCryptoStrength = cryptoStrength
      msAttachmentHint = attachmentHint
      msTcDisplay = tcDisplay
      msTcDisplayContentType = tcDisplayContentType
      msTcDisplayPNGCharacteristics = tcDisplayPNGCharacteristics
  msAttestationRootCertificates <- case NE.nonEmpty attestationRootCertificates of
    -- > When supporting surrogate basic attestation only, no attestation trust anchor is required/used. So this array MUST be empty in that case.
    -- This will never be the case, because if only surrogate basic attestation is used, then decodeAttestationTypes above will have returned (Left Nothing) already
    Nothing -> Left $ Just "attestationRootCertificates should not be empty"
    Just certs -> first Just $ traverse decodeCertificate certs
  msIcon <- first Just $ traverse decodeIcon icon
  let msSupportedExtensions = supportedExtensions
      msAuthenticatorGetInfo = authenticatorGetInfo
  pure $ StatementTypes.MetadataStatement {..}
  where
    -- Turns a non-empty list of 'Registry.AuthenticatorAttestationType' into a non-empty list of 'WebauthnAttestationType'.
    -- If the authenticator doesn't support any webauthn attestation types,
    -- `Left Nothing` is returned, indicating that this authenticator should be ignored
    decodeAttestationTypes ::
      NonEmpty Registry.AuthenticatorAttestationType ->
      Either (Maybe Text) (NonEmpty WebauthnAttestationType)
    decodeAttestationTypes types = case NE.nonEmpty $ mapMaybe transform $ NE.toList types of
      Nothing -> Left Nothing
      Just result -> Right result
      where
        transform :: Registry.AuthenticatorAttestationType -> Maybe WebauthnAttestationType
        transform Registry.ATTESTATION_BASIC_FULL = Just WebauthnAttestationBasic
        transform Registry.ATTESTATION_ATTCA = Just WebauthnAttestationAttCA
        transform _ = Nothing

    -- Decodes the PNG bytes of an [icon](https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.0-ps-20210518.html#dom-metadatastatement-icon) field of a metadata statement
    decodeIcon :: IDL.DOMString -> Either Text BS.ByteString
    decodeIcon dataUrl = case Text.stripPrefix "data:image/png;base64," dataUrl of
      Nothing -> Left $ "Icon decoding failed because there is no \"data:image/png;base64,\" prefix: " <> dataUrl
      Just suffix ->
        -- TODO: Use non-lenient decoding, it's only needed because of a spec violation,
        -- see <https://github.com/tweag/haskell-fido2/issues/68>
        Right $ Base64.decodeLenient (encodeUtf8 suffix)
