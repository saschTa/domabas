import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadNavigationFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('Flutter SDK root is required for font loading');
  }
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium']) {
    final file = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
    );
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
  }
  await loader.load();
}
