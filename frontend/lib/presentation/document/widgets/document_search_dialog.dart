import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../../../domain/document/models/document_search.dart';
import '../../../ui/glacier.dart';
import '../cubits/documents_cubit.dart';
import '../models/document_search_draft.dart';
import 'document_filter_dialog.dart';

final class DocumentSearchDialog extends StatefulWidget {
  const DocumentSearchDialog({
    super.key,
    required this.documents,
    required this.isCurrent,
    required this.onApply,
    required this.onCancel,
    this.vocabulary,
    this.libraryName = '',
  });
  final DocumentsCubit documents;
  final DocumentVocabularyRepository? vocabulary;
  final bool Function() isCurrent;
  final ValueChanged<DocumentSearchDraft> onApply;
  final VoidCallback onCancel;
  final String libraryName;
  @override
  State<DocumentSearchDialog> createState() => _DocumentSearchDialogState();
}

final class _DocumentSearchDialogState extends State<DocumentSearchDialog> {
  late DocumentSearchDraft _draft = DocumentSearchDraft.fromState(
    widget.documents.state,
  );
  late final _query = TextEditingController(
    text: widget.documents.state.rawTerm,
  );
  late final _sender = TextEditingController(
    text: _draft.desiredCriteria.sender,
  );
  late final _recipient = TextEditingController(
    text: _draft.desiredCriteria.recipient,
  );
  String? _error;
  RawDialogRoute<void>? _lookupRoute;
  NavigatorState? _lookupNavigator;
  bool get _owns => mounted && !widget.documents.isClosed && widget.isCurrent();

  @override
  void dispose() {
    final route = _lookupRoute;
    final navigator = _lookupNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
    _query.dispose();
    _sender.dispose();
    _recipient.dispose();
    super.dispose();
  }

  void _clear() {
    if (!_owns) return;
    _query.clear();
    _sender.clear();
    _recipient.clear();
    setState(() {
      _draft = DocumentSearchDraft(desiredCriteria: DocumentSearchCriteria());
      _error = null;
    });
  }

  void _apply() {
    if (!_owns) return;
    if ([_query, _sender, _recipient].any(
      (controller) =>
          controller.value.composing.isValid &&
          !controller.value.composing.isCollapsed,
    )) {
      return;
    }
    final error =
        DocumentSearchCriteria.validateTerm(_query.text) ??
        DocumentSearchCriteria.validateAddress(_sender.text) ??
        DocumentSearchCriteria.validateAddress(_recipient.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onApply(
      _draft.withCriteria(
        _draft.desiredCriteria.copyWith(
          query: _query.text,
          sender: _sender.text,
          recipient: _recipient.text,
        ),
      ),
    );
  }

  Future<void> _values() async {
    final repository = widget.vocabulary;
    if (!_owns || repository == null || _lookupRoute != null) return;
    _draft = _draft.withCriteria(
      _draft.desiredCriteria.copyWith(
        query: _query.text,
        sender: _sender.text,
        recipient: _recipient.text,
      ),
    );
    final native = GlacierNativePresentationScope.maybeOf(context);
    final navigator = _lookupNavigator = Navigator.of(context);
    late final RawDialogRoute<void> route;
    bool current() =>
        mounted &&
        !widget.documents.isClosed &&
        _lookupRoute == route &&
        route.navigator == navigator &&
        route.isCurrent;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      transitionDuration: Duration.zero,
      pageBuilder: (routeContext, _, _) => glacierDialogBackdrop(
        routeContext,
        (_) => SafeArea(
          child: DocumentFilterDialog(
            documents: widget.documents,
            repository: repository,
            isCurrent: current,
            initialDraft: _draft,
            onDraftChanged: (value) {
              if (!current()) return;
              setState(() => _draft = value);
              _sender.text = value.desiredCriteria.sender;
              _recipient.text = value.desiredCriteria.recipient;
            },
            onClose: () {
              if (current()) navigator.pop();
            },
          ),
        ),
        native: native,
      ),
    );
    _lookupRoute = route;
    await navigator.push(route);
    if (!mounted || _lookupRoute != route) return;
    _lookupRoute = null;
    _lookupNavigator = null;
  }

  @override
  Widget build(BuildContext context) {
    final criteria = _draft.desiredCriteria;
    return Dialog(
      key: const Key('documentSearchDialog'),
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      child: GlacierSearchDialog(
        controller: _query,
        fieldKey: const Key('documentSearchTerm'),
        applyKey: const Key('applyDocumentSearch'),
        contextLabel: widget.libraryName.isEmpty
            ? 'Documents'
            : '${widget.libraryName} · Documents',
        summary:
            criteria.filterCount == 0 &&
                _sender.text.isEmpty &&
                _recipient.text.isEmpty
            ? ''
            : 'Filters ready to apply',
        onChanged: (_) => setState(() => _error = null),
        error: _error,
        onApply: _apply,
        onClear: _clear,
        onCancel: widget.onCancel,
        filters: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlacierSearchFilterGroup(
              label: 'Document types · match any',
              options: DocumentKind.values.map((kind) => kind.label).toList(),
              selected: criteria.kinds.map((kind) => kind.label).toList(),
              onChanged: (label, selected) {
                final kind = DocumentKind.values.firstWhere(
                  (kind) => kind.label == label,
                );
                setState(
                  () => _draft = _draft.withCriteria(
                    criteria.copyWith(
                      kinds: selected
                          ? {...criteria.kinds, kind}
                          : criteria.kinds.where((value) => value != kind),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Tags · match all',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in criteria.tags)
                  GlacierTag(
                    label: tag,
                    onDeleted: () =>
                        setState(() => _draft = _draft.removeTag(tag)),
                  ),
                GlacierButton(
                  label: criteria.tags.isEmpty
                      ? 'Choose tags and people'
                      : 'More library values',
                  icon: Icons.manage_search,
                  onPressed: widget.vocabulary == null ? null : _values,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Sender and recipient'),
              children: [
                _address(
                  'Sender',
                  _sender,
                  criteria.senderMatch,
                  (match) => setState(
                    () => _draft = _draft.withCriteria(
                      criteria.copyWith(senderMatch: match),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _address(
                  'Recipient',
                  _recipient,
                  criteria.recipientMatch,
                  (match) => setState(
                    () => _draft = _draft.withCriteria(
                      criteria.copyWith(recipientMatch: match),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DocumentSort>(
              isExpanded: true,
              initialValue: criteria.sort,
              key: ValueKey(criteria.sort),
              decoration: const InputDecoration(labelText: 'Sort'),
              items: DocumentSort.values
                  .map(
                    (sort) => DropdownMenuItem(
                      value: sort,
                      child: Text(
                        sort.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (sort) {
                if (sort != null) {
                  setState(
                    () => _draft = _draft.withCriteria(
                      criteria.copyWith(sort: sort),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _address(
    String label,
    TextEditingController controller,
    DocumentAddressMatch match,
    ValueChanged<DocumentAddressMatch> onMatch,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierField(
        label: label,
        controller: controller,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<DocumentAddressMatch>(
        initialValue: match,
        key: ValueKey('$label-$match'),
        decoration: InputDecoration(labelText: 'Match ${label.toLowerCase()}'),
        items: const [
          DropdownMenuItem(
            value: DocumentAddressMatch.contains,
            child: Text('Contains'),
          ),
          DropdownMenuItem(
            value: DocumentAddressMatch.exact,
            child: Text('Exact address or name'),
          ),
        ],
        onChanged: (value) {
          if (value != null) onMatch(value);
        },
      ),
    ],
  );
}
