import 'package:flutter/services.dart';

final class IdentityClipboardDataSource {
  Future<bool> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } on PlatformException {
      return false;
    }
  }
}
