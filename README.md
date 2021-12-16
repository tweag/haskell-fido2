# Haskell WebAuthn Library

This library implements the
[Web Authentication Relying Party specification Level 2][spec]. The goal of Web
Authentication (WebAuthn) is to bring passwordless login/second factor
authentication to the web, logging in using a FIDO U2F Security Key, finger
print scanner and some other authenticator.

## Setting up the environment
We assume Nix is used for the development of this library. If not using Nix,
take a look at `default.nix` for the dependencies and GHC version. All
instructions below assume the use of Nix.

### Nix Caches
We highly recommend using the IOHK Binary Cache to avoid building of several
copies of GHC. Setting up the IOHK binary cache is easily done following the
[instructions][cache] provided by IOHK.

Additionally, Tweag provides a Cachix cache for the library itself and all
non-Haskell dependencies, setting up the `tweag-haskell-fido2` cache can be
done using the [instructions][cachix] provided by Cachix.

### Nix Shell
The Nix shell provides all libraries and tools required to build the library,
tests, and example server. Simply call `nix-shell` to enter a shell. If the
binary caches have been configured properly, this should take little time. If
they have not been properly configured, entering the Nix shell will take
multiple hours.

All further instructions in this README assume that you are in a Nix shell.

## Developing the Library
The [Haskell Language Server (hls)][hls] and [Ormolu][ormolu] are highly
recommended for the development of this library. The hls
[documentation][hls-editor] describes how to configure your editor to use it.
We also recommend enabling auto-format using Ormolu for your editor. We do,
however, also provide a bash script in `bin/autoformat.sh` that uses Ormolu to
format all Haskell source files in the repository.

Code not formatted using Ormolu will be rejected in CI.

## Running the tests
Tests are provided in the `tests` directory. Running these tests is done via
cabal:
```bash
cabal run test-suite:tests
```

## Running the demo
The library comes with an example implementation for a server that makes use of
it, which can be found in the `server` directory. All dependencies required to
build the example server are included in the Nix shell.
```bash
cd server
./run.sh
```

Changes to the server's source files automatically trigger a rebuild of the
server.

## Testing with an Authenticator
The easiest way to test the server, or your own application, is to use the
Chrome WebAuthn development tool. Simply open the Chrome DevTools, click on the
three dots in the top right, select "More tools -> WebAuthn", and then enable
the virtual environment.

Testing with a physical authenticator is easiest using an Android or iOS phone
supporting it, or a dedicated token like a [YubiKey][yubikey] or the
open-source [SoloKey][solokey]. Testing with a phone requires setting up a
certificate for the domain of the relying party as WebAuthn only works via
https, with an exception being made for `localhost`.

## Acknowledgements
The test files in `tests/responses/` were not created by Tweag, but
were instead copied from existing WebAuthn libraries. Notably the
[.NET][dotnet] and [python][python] libraries by the .NET foundation and Duo
Labs respectively. Their licenses can be found below.

## LICENSES
### All files except those explicitly licensed otherwise
```text
Copyright
  2020 - 2021 Arian van Putten
  2021 -      Tweag I/O

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
```

### All files in the `tests/responses` directory
```text
Copyright (c) 2017-2021 Duo Security, Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

```text
MIT License

Copyright (c) .NET Foundation and Contributors
All Rights Reserved

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

[cache]: https://input-output-hk.github.io/haskell.nix/tutorials/getting-started.html#setting-up-the-binary-cache
[cachix]: https://app.cachix.org/cache/tweag-haskell-fido2
[dotnet]: https://github.com/passwordless-lib/fido2-net-lib
[hls-editor]: https://haskell-language-server.readthedocs.io/en/latest/configuration.html#configuring-your-editor
[hls]: https://github.com/haskell/haskell-language-server
[ormolu]: https://github.com/tweag/ormolu
[python]: https://github.com/duo-labs/py_webauthn
[solokey]: https://solokeys.com/
[spec]: https://www.w3.org/TR/webauthn-2/
[yubikey]: https://www.yubico.com/
