{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}

-- | Stability: experimental
-- This module contains a partial implementation of the
-- [COSE_Key](https://datatracker.ietf.org/doc/html/rfc8152#section-7) format,
-- limited to what is needed for Webauthn, and in a structured way.
module Crypto.WebAuthn.Cose.PublicKey
  ( -- * Public key
    UncheckedPublicKey (..),
    checkPublicKey,
    PublicKey (PublicKey),
    EdDSAKeyBytes (..),
    EdDSAPublicKey (..),
    ECDSAPublicKey (..),
    RSAPublicKey (..),

    -- * COSE Elliptic Curves
    CoseCurveEdDSA (..),
    coordinateSizeEdDSA,
    CoseCurveECDSA (..),
    toCryptCurveECDSA,
    fromCryptCurveECDSA,
    coordinateSizeECDSA,
  )
where

import qualified Crypto.PubKey.ECC.Prim as ECC
import qualified Crypto.PubKey.ECC.Types as ECC
import qualified Crypto.PubKey.Ed25519 as Ed25519
import Crypto.WebAuthn.Internal.ToJSONOrphans (PrettyHexByteString (PrettyHexByteString))
import Data.Aeson (ToJSON)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Generics (Generic)

-- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.2)
-- This contains the public key bytes.
newtype EdDSAKeyBytes = EdDSAKeyBytes {unEdDSAKeyBytes :: BS.ByteString}
  deriving newtype (Eq)
  deriving (Show, ToJSON) via PrettyHexByteString

-- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.2)
-- EdDSA Signature Algorithm
--
-- [RFC8032](https://datatracker.ietf.org/doc/html/rfc8032) describes the
-- elliptic curve signature scheme Edwards-curve
-- Digital Signature Algorithm (EdDSA). In that document, the signature
-- algorithm is instantiated using parameters for edwards25519 and
-- edwards448 curves. The document additionally describes two variants
-- of the EdDSA algorithm: Pure EdDSA, where no hash function is applied
-- to the content before signing, and HashEdDSA, where a hash function
-- is applied to the content before signing and the result of that hash
-- function is signed. For EdDSA, the content to be signed (either the
-- message or the pre-hash value) is processed twice inside of the
-- signature algorithm. For use with COSE, only the pure EdDSA version
-- is used.
--
-- Security considerations are [here](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.2.1)
data EdDSAPublicKey = EdDSAPublicKey
  { -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.2)
    -- The elliptic curve to use
    eddsaCurve :: CoseCurveEdDSA,
    -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.2)
    -- This contains the public key bytes.
    eddsaX :: EdDSAKeyBytes
  }
  deriving (Eq, Show, Generic, ToJSON)

-- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.1)
-- ECDSA Signature Algorithm
--
-- This document defines ECDSA to work only with the curves P-256,
-- P-384, and P-521. Future documents may define it to work with other
-- curves and points in the future.
--
-- In order to promote interoperability, it is suggested that SHA-256 be
-- used only with curve P-256, SHA-384 be used only with curve P-384,
-- and SHA-512 be used with curve P-521. This is aligned with the recommendation in
-- [Section 4 of RFC5480](https://datatracker.ietf.org/doc/html/rfc5480#section-4).
--
-- Security considerations are [here](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.1.1)
data ECDSAPublicKey = ECDSAPublicKey
  { -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1.1)
    -- The elliptic curve to use
    ecdsaCurve :: CoseCurveECDSA,
    -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1.1)
    -- This contains the x-coordinate for the EC point. The integer is
    -- converted to a byte string as defined in [SEC1]. Leading zero
    -- octets MUST be preserved.
    ecdsaX :: Integer,
    -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1.1)
    -- This contains the value of the
    -- y-coordinate for the EC point. When encoding the value y, the
    -- integer is converted to an byte string (as defined in
    -- [SEC1](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#ref-SEC1))
    -- and encoded as a CBOR bstr. Leading zero octets MUST be
    -- preserved.
    ecdsaY :: Integer
  }
  deriving (Eq, Show, Generic, ToJSON)

-- | [(spec)](https://www.rfc-editor.org/rfc/rfc8812.html#section-2)
-- [RSASSA-PKCS1-v1_5](https://www.rfc-editor.org/rfc/rfc8017#section-8.2) Signature Algorithm
--
-- A key of size 2048 bits or larger MUST be used with these algorithms.
-- Security considerations are [here](https://www.rfc-editor.org/rfc/rfc8812.html#section-5)
data RSAPublicKey = RSAPublicKey
  { -- | [(spec)](https://www.rfc-editor.org/rfc/rfc8230.html#section-4)
    -- The RSA modulus n is a product of u distinct odd primes
    -- r_i, i = 1, 2, ..., u, where u >= 2
    rsaN :: Integer,
    -- | [(spec)](https://www.rfc-editor.org/rfc/rfc8230.html#section-4)
    -- The RSA public exponent e is an integer between 3 and n - 1 satisfying
    -- GCD(e,\\lambda(n)) = 1, where \\lambda(n) = LCM(r_1 - 1, ..., r_u - 1)
    rsaE :: Integer
  }
  deriving (Eq, Show, Generic, ToJSON)

-- | [(spec)](https://www.w3.org/TR/webauthn-2/#credentialpublickey)
-- A structured representation of a [COSE_Key](https://datatracker.ietf.org/doc/html/rfc8152#section-7)
-- limited to what is know to be necessary for Webauthn public keys for the
-- [credentialPublicKey](https://www.w3.org/TR/webauthn-2/#credentialpublickey) field,
-- and without any signing algorithm parameters like hashes. Due to the raw
-- nature of parameters, this type is labeled as unchecked. Parameters are
-- checked by using the 'checkPublicKey' function, returning a t'PublicKey'
-- type.
data UncheckedPublicKey
  = -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.2)
    -- EdDSA Signature Algorithm
    --
    -- Security considerations are [here](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.2.1)
    PublicKeyEdDSA EdDSAPublicKey
  | -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.1)
    -- ECDSA Signature Algorithm
    --
    -- Security considerations are [here](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-2.1.1)
    PublicKeyECDSA ECDSAPublicKey
  | -- | [(spec)](https://www.rfc-editor.org/rfc/rfc8812.html#section-2)
    -- [RSASSA-PKCS1-v1_5](https://www.rfc-editor.org/rfc/rfc8017#section-8.2) Signature Algorithm
    --
    -- Security considerations are [here](https://www.rfc-editor.org/rfc/rfc8812.html#section-5)
    PublicKeyRSA RSAPublicKey
  deriving (Eq, Show, Generic)

-- | An arbitrary and potentially unstable JSON encoding, only intended for
-- logging purposes. To actually encode and decode structures, use the
-- "Crypto.WebAuthn.Encoding" modules
deriving instance ToJSON UncheckedPublicKey

-- | Same as 'UncheckedPublicKey', but checked to be valid using
-- 'checkPublicKey'.
newtype PublicKey = CheckedPublicKey UncheckedPublicKey
  deriving newtype (Eq, Show)

-- | An arbitrary and potentially unstable JSON encoding, only intended for
-- logging purposes. To actually encode and decode structures, use the
-- "Crypto.WebAuthn.Encoding" modules
deriving newtype instance ToJSON PublicKey

-- | Returns the 'UncheckedPublicKey' for a t'PublicKey'
pattern PublicKey :: UncheckedPublicKey -> PublicKey
pattern PublicKey k <- CheckedPublicKey k

{-# COMPLETE PublicKey #-}

-- | Checks whether an 'UncheckedPublicKey' is valid. This is the only way to construct a t'PublicKey'
checkPublicKey :: UncheckedPublicKey -> Either Text PublicKey
checkPublicKey key@(PublicKeyEdDSA EdDSAPublicKey {..})
  | actualSize == expectedSize = Right $ CheckedPublicKey key
  | otherwise =
      Left $
        "EdDSA public key for curve "
          <> Text.pack (show eddsaCurve)
          <> " didn't have the expected size of "
          <> Text.pack (show expectedSize)
          <> " bytes, it has "
          <> Text.pack (show actualSize)
          <> " bytes instead: "
          <> Text.pack (show eddsaX)
  where
    actualSize = BS.length $ unEdDSAKeyBytes eddsaX
    expectedSize = coordinateSizeEdDSA eddsaCurve
checkPublicKey key@(PublicKeyECDSA ECDSAPublicKey {..})
  | ECC.isPointValid curve point = Right $ CheckedPublicKey key
  | otherwise =
      Left $
        "ECDSA public key point is not valid for curve "
          <> Text.pack (show ecdsaCurve)
          <> ": "
          <> Text.pack (show point)
  where
    curve = ECC.getCurveByName (toCryptCurveECDSA ecdsaCurve)
    point = ECC.Point ecdsaX ecdsaY
checkPublicKey key = Right $ CheckedPublicKey key

-- | COSE elliptic curves that can be used with EdDSA
data CoseCurveEdDSA
  = -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1)
    -- Ed25519 for use w/ EdDSA only
    CoseCurveEd25519
  deriving (Eq, Show, Enum, Bounded, Generic)

-- | An arbitrary and potentially unstable JSON encoding, only intended for
-- logging purposes. To actually encode and decode structures, use the
-- "Crypto.WebAuthn.Encoding" modules
deriving instance ToJSON CoseCurveEdDSA

-- | Returns the size of a coordinate point for a specific EdDSA curve in bytes.
coordinateSizeEdDSA :: CoseCurveEdDSA -> Int
coordinateSizeEdDSA CoseCurveEd25519 = Ed25519.publicKeySize

-- | COSE elliptic curves that can be used with ECDSA
data CoseCurveECDSA
  = -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1)
    -- NIST P-256 also known as secp256r1
    CoseCurveP256
  | -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1)
    -- NIST P-384 also known as secp384r1
    CoseCurveP384
  | -- | [(spec)](https://datatracker.ietf.org/doc/html/draft-ietf-cose-rfc8152bis-algs-12#section-7.1)
    -- NIST P-521 also known as secp521r1
    CoseCurveP521
  deriving (Eq, Show, Enum, Bounded, Generic)

-- | An arbitrary and potentially unstable JSON encoding, only intended for
-- logging purposes. To actually encode and decode structures, use the
-- "Crypto.WebAuthn.Encoding" modules
deriving instance ToJSON CoseCurveECDSA

-- | Converts a 'Cose.CoseCurveECDSA' to an 'ECC.CurveName'. The inverse
-- function is 'fromCryptCurveECDSA'
toCryptCurveECDSA :: CoseCurveECDSA -> ECC.CurveName
toCryptCurveECDSA CoseCurveP256 = ECC.SEC_p256r1
toCryptCurveECDSA CoseCurveP384 = ECC.SEC_p384r1
toCryptCurveECDSA CoseCurveP521 = ECC.SEC_p521r1

-- | Tries to converts a 'ECC.CurveName' to an 'Cose.CoseCurveECDSA'. The inverse
-- function is 'toCryptCurveECDSA'
fromCryptCurveECDSA :: ECC.CurveName -> Either Text CoseCurveECDSA
fromCryptCurveECDSA ECC.SEC_p256r1 = Right CoseCurveP256
fromCryptCurveECDSA ECC.SEC_p384r1 = Right CoseCurveP384
fromCryptCurveECDSA ECC.SEC_p521r1 = Right CoseCurveP521
fromCryptCurveECDSA curve =
  Left $
    "Curve "
      <> Text.pack (show curve)
      <> " is not a supported COSE ECDSA public key curve"

-- | Returns the size of a coordinate point for a specific ECDSA curve in bytes.
coordinateSizeECDSA :: CoseCurveECDSA -> Int
coordinateSizeECDSA curve = byteSize
  where
    bitSize = ECC.curveSizeBits (ECC.getCurveByName (toCryptCurveECDSA curve))
    byteSize = (bitSize + 7) `div` 8
