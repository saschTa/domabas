import 'package:domabas/domain/licenses/interfaces/third_party_license_repository.dart';
import 'package:domabas/domain/licenses/models/third_party_license.dart';

final class FakeThirdPartyLicenseRepository
    implements ThirdPartyLicenseRepository {
  FakeThirdPartyLicenseRepository({this.entries = const []});

  List<ThirdPartyLicense> entries;
  Future<List<ThirdPartyLicense>> Function()? onLoad;
  int reads = 0;

  @override
  Future<List<ThirdPartyLicense>> load() async {
    reads++;
    return onLoad == null ? entries : onLoad!();
  }
}
