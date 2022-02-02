### Next release: 0.4.0.0

* [#132](https://github.com/tweag/webauthn/pull/125) Preparations for future extension support:
  - Renames `SupportedAttestationStatementFormats` to
    `AttestationStatementFormatRegistry`
  - Introduce the `WebAuthnRegistries` type, currently only consisting of an
    `AttestationStatementFormatRegistry` and use it throughout instead of the
    latter
  - Replace `allSupportedFormats :: AttestationStatementFormatRegistry` with
    `supportedRegistries :: WebAuthnRegistries`
  - Make not only the registration response decoding function take a
    `WebAuthnRegistries`, but also the authentication response decoding, so
    that we later don't have to break compatibility when extensions are
    implemented

### 0.3.0.0

* [#125](https://github.com/tweag/webauthn/pull/125) Some small metadata type
  simplifications involving `msUpv` and `SomeMetadataEntry`
* [#126](https://github.com/tweag/webauthn/pull/126) Decrease lower bounds of
  many dependencies including `base`, adding compatibility with GHC 8.8

### 0.2.0.0

* [#115](https://github.com/tweag/webauthn/pull/115) Increase the upper bound
  of the supported Aeson versions, allowing the library to be built with Aeson
  2.0. Drop the deriving-aeson dependency.
* [#117](https://github.com/tweag/webauthn/pull/117) Rename and expand
  documentation for attestation statement format errors. Some unused errors
  were removed.

### 0.1.1.0

* [#111](https://github.com/tweag/webauthn/pull/111) Support the
  [`transports`](https://www.w3.org/TR/webauthn-2/#dom-authenticatorattestationresponse-transports-slot)
  field, allowing servers to store information from the browser on how
  authenticators were communicated with (e.g. internal, NFC, etc.). When users
  log in, this information can then be passed along in [Credential
  Descriptors](https://www.w3.org/TR/webauthn-2/#dictdef-publickeycredentialdescriptor),
  ensuring that only the transports initially registered as supported by the
  authenticator may be used. This is recommended by the standard.
* [#112](https://github.com/tweag/webauthn/pull/112) Decrease lower bounds for
  aeson and unordered-containers.
