import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class BundledThirdPartyLicenseDataSource {
  const BundledThirdPartyLicenseDataSource({
    required this._bundle,
    required this._licenses,
  });

  final AssetBundle _bundle;
  final Stream<LicenseEntry> Function() _licenses;

  Future<Map<String, dynamic>> loadInventory() async {
    const asset = 'assets/licenses/third-party.json';
    try {
      return jsonDecode(await _bundle.loadString(asset))
          as Map<String, dynamic>;
    } catch (_) {
      _bundle.evict(asset);
      rethrow;
    }
  }

  Stream<LicenseEntry> runtimeLicenses() => _licenses();
}
