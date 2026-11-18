import 'package:widgetbook/widgetbook.dart';
import 'package:domabas/ui/glacier/glacier_surfaces.dart';
import 'package:flutter/widgets.dart';

import 'catalog_case.dart';
import 'foundation_cases.dart';
import 'workflow_cases.dart';
import 'documents_cases.dart';
import 'settings_cases.dart';
import 'desktop_cases.dart';
import 'native_cases.dart';
import 'activity_dock_cases.dart';
import 'mobile_catalog.dart';
import 'mobile_foundation_cases.dart';
import 'mobile_documents_cases.dart';
import 'mobile_workflow_cases.dart';
import 'mobile_settings_cases.dart';

List<CatalogCase> catalogCases() => [
  ...desktopCases(),
  ...nativeCases(),
  ...mobileFoundationCases(),
  ...mobileDocumentsCases(),
  ...mobileWorkflowCases(),
  ...mobileSettingsCases(),
  ...foundationCases(),
  ...activityDockCases(),
  ...documentsCases(),
  ...workflowCases(),
  ...settingsCases(),
];

List<WidgetbookNode> catalogDirectories(List<CatalogCase> cases) {
  final domains = <String, Map<String, List<CatalogCase>>>{};
  for (final entry in cases) {
    domains
        .putIfAbsent(entry.domain, () => {})
        .putIfAbsent(entry.component, () => [])
        .add(entry);
  }
  return [
    for (final domain in domains.entries)
      WidgetbookFolder(
        name: domain.key,
        children: [
          for (final component in domain.value.entries)
            WidgetbookComponent(
              name: component.key,
              useCases: [
                for (final entry in component.value)
                  WidgetbookUseCase(
                    name: entry.name,
                    builder: (_) => MobileCatalogScope(
                      routes: {
                        for (final route in cases) route.id: route.builder,
                      },
                      child: GlacierActivityBackdrop(
                        atmosphere: true,
                        child: entry.mobile
                            ? MobileCatalogHost(
                                child: Builder(builder: entry.builder),
                              )
                            : Builder(builder: entry.builder),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
  ];
}
