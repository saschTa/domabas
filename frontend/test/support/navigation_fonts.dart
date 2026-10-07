import 'package:flutter/services.dart';

Future<void> loadNavigationFonts() async {
  for (final (family, files) in [
    ('DMSans', ['DMSans-Regular.ttf', 'DMSans-SemiBold.ttf']),
    ('BarlowCondensed', ['BarlowCondensed-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
}
