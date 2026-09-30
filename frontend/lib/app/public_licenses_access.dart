import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/licenses/datasources/bundled_third_party_license_data_source.dart';
import '../data/licenses/repos/bundled_third_party_license_repository.dart';
import '../presentation/licenses/cubits/licenses_cubit.dart';
import '../presentation/licenses/views/licenses_screen.dart';
import '../ui/domabas_ui.dart';

final class PublicLicensesFooter extends StatelessWidget {
  const PublicLicensesFooter({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppLayout.pageInset(MediaQuery.sizeOf(context).width),
      0,
      AppLayout.pageInset(MediaQuery.sizeOf(context).width),
      8,
    ),
    child: Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const Key('publicLicenses'),
        onPressed: () {
          FocusScope.of(context).unfocus();
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => const _PublicLicensesPage(),
            ),
          );
        },
        icon: const Icon(Icons.article_outlined, size: 18),
        label: const Text('Licenses'),
      ),
    ),
  );
}

final class _PublicLicensesPage extends StatefulWidget {
  const _PublicLicensesPage();

  @override
  State<_PublicLicensesPage> createState() => _PublicLicensesPageState();
}

final class _PublicLicensesPageState extends State<_PublicLicensesPage> {
  late final _licenses = LicensesCubit(
    BundledThirdPartyLicenseRepository(
      dataSource: BundledThirdPartyLicenseDataSource(
        bundle: rootBundle,
        licenses: () => LicenseRegistry.licenses,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_licenses.load());
  }

  @override
  void dispose() {
    unawaited(_licenses.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: AppPaperCanvas(
      child: SafeArea(
        child: LicensesScreen(cubit: _licenses, eyebrow: 'About Domabas'),
      ),
    ),
  );
}
