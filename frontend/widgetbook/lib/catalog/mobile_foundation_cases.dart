import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'mobile_catalog.dart';

List<CatalogCase> mobileFoundationCases() => [
  mobileComponentCase(
    id: 'document-row',
    title: 'Document row',
    widgetType: 'GlacierMobileRecordRow',
    referenceComponent: 'document-row',
    builder: (context) => mobileCatalogShell(
      context,
      title: 'Documents',
      child: GlacierMobileRecordRow(
        title: 'Forma Studio',
        detail: 'Invoice · 12 November',
        icon: Icons.description_outlined,
        onTap: () =>
            mobileCatalogNavigate(context, 'reader', arguments: 'forma'),
      ),
    ),
  ),
  for (final entry in <(String, String, WidgetBuilder)>[
    (
      'mobile-shell',
      'GlacierMobileShell',
      (context) => mobileCatalogShell(
        context,
        title: 'Documents',
        child: _body(context),
      ),
    ),
    (
      'mobile-navigation',
      'GlacierMobileNavigation',
      (context) => mobileCatalogShell(
        context,
        title: 'Documents',
        child: _body(context),
      ),
    ),
    (
      'mobile-header',
      'GlacierMobileHeader',
      (context) => mobileCatalogShell(
        context,
        title: 'Documents',
        child: _body(context),
      ),
    ),
    (
      'search-entry',
      'GlacierMobileSearchEntry',
      (context) => mobileCatalogShell(
        context,
        title: 'Documents',
        child: GlacierMobileSearchEntry(
          onPressed: () => mobileCatalogNavigate(context, 'search'),
        ),
      ),
    ),
    ('glass-sheet', 'GlacierMobileSheet', (context) => _SheetExample()),
    (
      'continuation',
      'GlacierMobileContinuation',
      (context) => mobileCatalogShell(
        context,
        title: 'Documents',
        child: GlacierMobileContinuation(
          label: '6 of 12 documents',
          onLoadMore: () {},
        ),
      ),
    ),
    (
      'recovery-notice',
      'GlacierMobileNotice',
      (context) => mobileCatalogShell(
        context,
        title: 'Properties & links',
        child: GlacierMobileNotice(
          title: 'Save outcome unknown',
          message: 'Check the saved value before trying again. Your draft remains here.',
          action: GlacierButton(label: 'Check saved value', onPressed: () {}),
        ),
      ),
    ),
    (
      'destination-row',
      'GlacierMobileRecordRow',
      (context) => mobileCatalogShell(
        context,
        title: 'More',
        selectedId: 'more',
        child: GlacierMobileRecordRow(
          title: 'Libraries',
          detail: 'Manage your document libraries',
          icon: Icons.library_books_outlined,
          onTap: () => mobileCatalogNavigate(context, 'libraries'),
        ),
      ),
    ),
    (
      'settings-field',
      'GlacierMobileField',
      (context) => mobileCatalogShell(
        context,
        title: 'Workload limits',
        selectedId: 'more',
        child: const GlacierMobileField(
          label: 'Worker slots',
          initialValue: '4',
          keyboardType: TextInputType.number,
        ),
      ),
    ),
    (
      'named-confirmation',
      'GlacierMobileConfirmation',
      (context) => _confirmation(context, 'delete'),
    ),
  ])
    mobileComponentCase(
      id: entry.$1,
      title: entry.$1,
      widgetType: entry.$2,
      referenceComponent: entry.$1,
      builder: entry.$3,
    ),
  mobileComponentCase(
    id: 'mobile-surface',
    title: 'Mobile surface',
    widgetType: 'GlacierMobileSurface',
    referenceComponent: 'mobile-shell',
    builder: (context) => mobileCatalogShell(
      context,
      title: 'Documents',
      child: const GlacierMobileSurface(child: Text('Personal library')),
    ),
  ),
  mobileComponentCase(
    id: 'mobile-action-bar',
    title: 'Mobile action bar',
    widgetType: 'GlacierMobileActionBar',
    referenceComponent: 'glass-sheet',
    builder: (context) => _SheetExample(),
  ),
  for (final state in [
    'delete',
    'discard',
    'signout',
    'revoke',
    'delete-email',
    'cancel-import',
    'delete-chat',
  ])
    mobileScreenCase(
      screen: 'confirm',
      state: state,
      title: 'Named confirmation',
      widgetType: 'GlacierMobileConfirmation',
      builder: (context) => _confirmation(context, state),
    ),
];

Widget _body(BuildContext context) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    GlacierMobileSearchEntry(
      onPressed: () => mobileCatalogNavigate(context, 'search'),
    ),
    const SizedBox(height: 20),
    GlacierMobileRecordRow(
      title: 'Forma Studio',
      detail: 'Invoice · 12 November',
      icon: Icons.description_outlined,
      onTap: () => mobileCatalogNavigate(context, 'reader'),
    ),
    const SizedBox(height: 8),
    GlacierMobileRecordRow(
      title: 'Home insurance',
      detail: 'Insurance · 10 November',
      icon: Icons.description_outlined,
      onTap: () =>
          mobileCatalogNavigate(context, 'reader', arguments: 'insurance'),
    ),
  ],
);

Widget _confirmation(BuildContext context, String state) {
  final value = switch (state) {
    'discard' => (
      'Discard this draft?',
      'The saved pages and unsent changes in Personal library will be removed.',
      'Discard draft',
      'Keep draft',
      'scan-review',
    ),
    'signout' => (
      'Sign out of Domabas?',
      'Your saved scan draft remains on this device for this account.',
      'Sign out',
      'Cancel',
      'account',
    ),
    'revoke' => (
      'Revoke this invitation?',
      'The code for jamie@example.com will stop granting access to Personal library.',
      'Revoke invitation',
      'Keep it',
      'invitations',
    ),
    'delete-email' => (
      'Delete Household inbox?',
      'Future email imports stop. Documents already accepted in Personal library remain.',
      'Delete connection',
      'Keep it',
      'email',
    ),
    'cancel-import' => (
      'Cancel this Paperless import?',
      'Documents already accepted in Personal library remain. No new originals will be retrieved.',
      'Cancel import',
      'Keep it',
      'paperless-import',
    ),
    'delete-chat' => (
      'Delete this conversation?',
      'Home insurance and its messages will be removed from Personal library. Original documents remain.',
      'Delete conversation',
      'Keep it',
      'chat-history',
    ),
    _ => (
      'Delete Forma Studio?',
      'This removes the document from Personal library. This action cannot be undone.',
      'Delete document',
      'Cancel',
      'reader',
    ),
  };
  return mobileCatalogShell(
    context,
    title: 'Named confirmation',
    onBack: () => Navigator.maybePop(context),
    showLibrary: false,
    child: GlacierMobileConfirmation(
      title: value.$1,
      message: value.$2,
      confirmLabel: value.$3,
      cancelLabel: value.$4,
      onCancel: () => mobileCatalogNavigate(context, value.$5),
      onConfirm: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fictional example confirmed. No account data changed.',
          ),
        ),
      ),
    ),
  );
}

class _SheetExample extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      mobileCatalogShell(context, title: 'Documents', child: _body(context)),
      const Positioned.fill(child: ColoredBox(color: Color(0x2409252B))),
      GlacierMobileSheet(
        header: const TextField(
          decoration: InputDecoration(
            hintText: 'Find a document',
            border: InputBorder.none,
          ),
        ),
        footer: GlacierMobileActionBar(
          hint: 'Enter applies · Esc clears, then closes',
          children: [
            GlacierButton(label: 'Cancel', onPressed: () {}),
            GlacierButton(
              label: 'Apply search',
              onPressed: () {},
              kind: GlacierButtonKind.primary,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search in Personal library',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            const GlacierMobileField(label: 'Sender', initialValue: ''),
            const GlacierMobileField(label: 'Recipient', initialValue: ''),
          ],
        ),
      ),
    ],
  );
}
