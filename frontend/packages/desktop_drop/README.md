# Domabas desktop file drop adapter

Derived from the published `desktop_drop` 0.8.4 archive:
https://pub.dev/api/archives/desktop_drop-0.8.4.tar.gz

Archive SHA-256: `47ded09c85909edfed644fd4cbb5051b040d0aed5c79e7e062ea4b3b7156dbe4`.
Upstream: https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_drop
The original Apache-2.0 license is retained in `LICENSE`.

This narrow derivative registers only Linux and Windows. It does not include
web handlers, directory walking, Android or macOS integration. Its owned Dart
controller replaces the singleton and widget API. Listener registration tokens
are captured before asynchronous portal resolution, invalidated on removal and
never transferred to replacement listeners. One outstanding portal RPC owns its
D-Bus client until response and close have both drained; its deadline reports
failure without releasing physical capacity early.

The Windows patch negotiates physical `CF_HDROP` and copy-only operations,
uses `STGMEDIUM.hGlobal` directly, queries and allocates each UTF-16 filename's
complete length, validates extraction and releases the acquired medium exactly
once. It removes path logging. Linux retains its copy-only GTK destination and
supplies complete path lists without directory traversal. Non-file URI results
are preserved as rejected candidates for the application to explain.

Linux requires GTK and a session D-Bus/file-transfer portal environment. Windows
requires the Flutter desktop C++ toolchain. Unit channel tests do not establish
native-host compilation or drag behavior.

The derived Dart dependency pins `dbus` 0.7.15, the compatible version selected by
the full application solver with XML 7 and the existing PDF package. Linux ingress
rejects empty, oversized, malformed UTF-8 or embedded-NUL payloads before copying
GTK selection data. Windows UTF-16 conversion checks both required and written
byte counts and preserves failed entries for application feedback.
