# Glucoid 1.4.1

A glucose badge for the KDE Plasma panel: latest value, trend arrow, delta
and reading age. Click for the detail card and settings. Optional thresholds,
mmol/l or mg/dl, configurable polling and stale-data indication.

## Connections and security

- **Juggluco / WireGuard (required)**: use the phone's numeric tunnel IP and
  the computer's actual WireGuard interface (for example wg0). Every socket
  is bound to that interface. A missing/down/fake interface or an alternative
  route cannot send the request outside WireGuard. This applies on Wi-Fi too.
- **Nightscout / HTTPS**: an independent Nightscout server with a valid TLS
  certificate. No WireGuard tunnel is required. Use a dedicated read token.

Access tokens, API secrets and public read-only access are supported. JWTs
exist only within one request job. API secrets use the api-secret SHA1 header.
Changing the server/source/interface/authentication clears the credential;
enter the credential belonging to the new connection. No automatic switch of
authentication style on a 401/403 response. Legacy token-query fallback is
limited to older supported API paths. The widget only reads from the server.

Requests have a 10-second total deadline, cancellation, 1 MiB decoded response
and 16 KiB header limits. Redirects and environment proxies are disabled.
Old responses cannot overwrite the display after a connection change.
Old HTTPS settings migrate to Nightscout; old HTTP settings require WireGuard.

## Requirements

The prebuilt 1.4.1 package targets **Linux x86_64, Ubuntu/Kubuntu 26.04,
Plasma 6.6 and Qt 6.10**, with system libcurl.so.4 (>=7.85). It includes a
native Qt/libcurl extension, not only QML. It requires no root privilege or
background service. Other architectures or older Qt require a source build
and are not covered by this binary. Do not install this binary into Qt 6.8.

Not a clinically validated medical device. Synthetic protocol tests do not
validate a real Nightscout installation, sensor or clinical decisions.

## Install

Download the matching .plasmoid and SHA-256 file from the GitHub release.

```sh
sha256sum -c glucoid-1.4.1.plasmoid.sha256
kpackagetool6 -t Plasma/Applet -i glucoid-1.4.1.plasmoid
# Existing installation:
kpackagetool6 -t Plasma/Applet -u glucoid-1.4.1.plasmoid
```

Restart Plasma or log out/in to load the updated native module. Configure
Glucoid from its gear or the widget's context menu. Existing settings are
preserved. Glucoid fetches its data independently; Glucoid Studio is not required.

## Build

C++20, CMake, Python 3, binutils/strip, zip, libcurl development headers >=7.85,
and Qt >=6.10 Core/Network/Qml/Quick/QuickTest/Test development packages.

```sh
cmake -S . -B build/native -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/native
python3 native/stage.py --project . --verify
tools/make-package.sh
```

The staged native module and its manifest must match the source and version;
packaging fails if they do not. The archive strips debug metadata and includes
licenses and notices. Native source is in native/, application QML in
plasmoid/, and the version's single source of truth is metadata.json.

## Tests

```sh
python3 tests/check-native-security.py --probe build/native/native-probe --output build/native/contracts
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_configgeneral.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_connectionsecurity.qml
```

The network contract uses only synthetic HTTPS servers, credentials and data.
It covers API/auth fallbacks, TLS rejection, redirects, response limits,
malformed data, credential scope, cancellation and settings-change races.
The isolated WireGuard tests and sanitizer evidence are maintained in the
private development workspace; they are not a runtime dependency.

## License

GPL-3.0-or-later. See LICENSE and THIRD_PARTY_NOTICES.md. Qt and libcurl are
dynamically linked system dependencies, not bundled libraries. You may rebuild
and replace the native extension from the complete application source.
