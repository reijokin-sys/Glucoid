# Third-party notices — Glucoid 1.3.1

Glucoid's own QML and native extension are GPL-3.0-or-later; see LICENSE.
Complete corresponding application source and build tools are available at
https://github.com/reijokin-sys/Glucoid/tree/v1.3.1 . Build requirements and
commands are in README.md. The native extension can be rebuilt and replaced;
there is no signature restriction on a modified build.

The package contains the application's own native shared object. Qt, libcurl,
libstdc++, libgcc and glibc are dynamically linked system libraries; their
shared objects are NOT bundled, copied or statically linked into this package.
System libraries and their transitive dependencies remain the responsibility
of the Linux distribution's package manager.

- Qt 6 Core, Network and QML: Copyright The Qt Company Ltd. and contributors.
  The open-source runtime libraries are used under LGPL-3.0; the LGPL text is
  in licenses/LGPL-3.0.txt and the GPL text is in LICENSE. Their source is
  available from https://download.qt.io/archive/qt/ and the distribution's
  qt6-base / qt6-declarative source packages. Qt headers and moc output used
  by this build are supplied by the same open-source Qt packages.
- libcurl: Copyright Daniel Stenberg and contributors, curl license.
  See licenses/curl.txt and https://curl.se/docs/copyright.html . The shared
  library is supplied by the distribution; no libcurl source is vendored.
- GNU runtime libraries: libstdc++ and libgcc are system libraries licensed
  under GPL-3.0-or-later with the GCC Runtime Library Exception; glibc is a
  system library under LGPL-2.1-or-later. None is redistributed in the widget.
  The distribution's copyright files provide the complete package inventory.

This notice was checked against the installed Ubuntu 26.04 packages'
copyright files and the native extension's ELF NEEDED entries. The distributed
archive is tested for the presence of LICENSE, this notice and both license
files. No other third-party binary or vendored component is included.
