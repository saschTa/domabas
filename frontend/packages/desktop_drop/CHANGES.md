# Domabas changes to desktop_drop

Domabas contributors modified the Apache-2.0 `desktop_drop` package for the
local version `0.8.4+domabas.1`. These changes are separate from upstream
`desktop_drop` 0.8.4, published by Mixin. The original copyright and Apache-2.0
license remain unchanged in [LICENSE](LICENSE).

The source is the published package archive:
https://pub.dev/api/archives/desktop_drop-0.8.4.tar.gz

Archive SHA-256:
`47ded09c85909edfed644fd4cbb5051b040d0aed5c79e7e062ea4b3b7156dbe4`.

Upstream repository:
https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_drop

## Modified files

- `lib/desktop_drop.dart` replaces the upstream exports and singleton/widget API
  with an owned controller, event values and disposable listener
  registrations. It bounds received batches and portal requests, preserves
  rejected path candidates, and drains portal responses and client closure
  before releasing capacity. Events are delivered only to the registrations
  captured when their request began.
- `linux/desktop_drop_plugin.cc` validates selection payloads before copying.
  Empty, oversized, malformed UTF-8 and embedded-NUL payloads produce a rejected
  event. The upstream GTK and portal transport remain in use.
- `windows/desktop_drop_plugin.cpp` accepts physical `CF_HDROP` files with
  copy-only drag negotiation. It reads the `STGMEDIUM` handle directly, bounds
  batch and filename lengths, allocates complete UTF-16 filenames, checks
  conversions and releases each acquired medium once. Path logging was removed.
- `pubspec.yaml` identifies the local derivative, disables package publication,
  registers only Linux and Windows, updates SDK constraints and pins `dbus`
  0.7.15. Dependencies for the removed platform and widget APIs were removed.
- `README.md` was replaced with Domabas integration and provenance documentation.

The upstream web, Android and macOS implementations, Dart `lib/src` API,
examples and package tests are not included in this derivative. The retained
Linux and Windows CMake files and public native headers are unchanged.

This file records the changes to the third-party package; it does not replace
its license. Each modified code or package configuration file also carries a
modification notice. Domabas includes this notice with the package's original
license in its offline Licenses screen.
