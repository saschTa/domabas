import '../models/third_party_license.dart';

abstract interface class ThirdPartyLicenseRepository {
  Future<List<ThirdPartyLicense>> load();
}
