import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'app/domabas_app.dart';
import 'app/native_server_app.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Lora',
    ], await rootBundle.loadString('assets/licenses/lora-ofl.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'PDFium and bundled dependencies',
    ], await rootBundle.loadString('assets/licenses/frontend-pdfium.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'OpenCV and bundled scanner dependencies',
    ], await rootBundle.loadString('assets/licenses/scanner-opencv.txt'));
  });
  runApp(kIsWeb ? const _DomabasBootstrap() : NativeServerApp.production());
}

final class _DomabasBootstrap extends StatefulWidget {
  const _DomabasBootstrap();

  @override
  State<_DomabasBootstrap> createState() => _DomabasBootstrapState();
}

final class _DomabasBootstrapState extends State<_DomabasBootstrap> {
  late final AppDependencies _dependencies = AppDependencies.production();

  @override
  void dispose() {
    _dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DomabasApp(
    appearance: _dependencies.appearance,
    auth: _dependencies.auth,
    uploads: _dependencies.uploads,
    authenticate: _dependencies.authenticate,
  );
}
