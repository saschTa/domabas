import 'dart:async';

import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:domabas/presentation/scanner/views/scanner_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'scanner_fixtures.dart';

void main() => runApp(const ScannerPreview());

class ScannerPreview extends StatefulWidget {
  const ScannerPreview({super.key});
  @override
  State<ScannerPreview> createState() => _ScannerPreviewState();
}

class _ScannerPreviewState extends State<ScannerPreview> {
  final camera = FixtureScannerCamera();
  late final repository = FixtureScanRepository(
    initial: ScanDraft(
      id: 'preview',
      revision: 1,
      properties: scanProperties({
        'title': 'Quarterly project notes',
        'description': 'Scanned pages ready for review.',
        'tags': <String>['project', 'review'],
        'documentDate': '2026-09-18',
      }),
      pages: [
        ScanPage(
          id: 'preview-red',
          width: 200,
          height: 300,
          thumbnail: scanJpeg(200, 300),
        ),
        ScanPage(
          id: 'preview-green',
          width: 400,
          height: 200,
          thumbnail: scanJpeg(400, 200, red: 20, green: 230),
        ),
      ],
    ),
  );
  late final cubit = ScannerCubit(
    camera: camera,
    repository: repository,
    allowed: true,
  );
  bool dark = false;
  @override
  void dispose() {
    unawaited(camera.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: ScannerScreen(
      cubit: cubit,
      previewBuilder: (_) => const ColoredBox(
        color: Color(0xffcddfd3),
        child: Center(child: Icon(Icons.description_outlined, size: 120)),
      ),
      canReadDocuments: true,
      appearanceAction: IconButton(
        tooltip: 'Toggle preview appearance',
        onPressed: () => setState(() => dark = !dark),
        icon: const Icon(Icons.brightness_6_outlined),
      ),
    ),
  );
}
