import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../../../domain/document/models/document_upload_validation.dart';
import '../../../domain/document/models/document_vocabulary.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/document_vocabulary_cubit.dart';
import '../cubits/documents_cubit.dart';
import 'document_search_widgets.dart';

final class DocumentFilterDialog extends StatefulWidget {
  const DocumentFilterDialog({
    super.key,
    required this.documents,
    required this.repository,
    required this.isCurrent,
    required this.onClose,
  });
  final DocumentsCubit documents;
  final DocumentVocabularyRepository repository;
  final bool Function() isCurrent;
  final VoidCallback onClose;
  @override
  State<DocumentFilterDialog> createState() => _DocumentFilterDialogState();
}

final class _DocumentFilterDialogState extends State<DocumentFilterDialog>
    with WidgetsBindingObserver {
  late final _lookup = DocumentVocabularyCubit(widget.repository);
  late final _scroll = _DocumentVocabularyScrollController(_correctLayout);
  final _query = TextEditingController();
  final _headingFocus = FocusNode();
  final _rowFocus = <String, FocusNode>{};
  double _rowExtent = 64, _lastHeaderExtent = 0, _headerExtent = 0;
  (String, double)? _anchor;
  bool _syncingQuery = false;
  String? _selectionNotice;
  bool get _owns => mounted && !widget.documents.isClosed && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _query.addListener(_edited);
    _scroll.addListener(_scrolled);
    _lookup.viewport = () =>
        DocumentVocabularyViewport(firstVisibleIndex: _visibleIndex());
    _lookup.beforeRelease = _release;
    unawaited(_lookup.submit());
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  int _visibleIndex() => !_scroll.hasClients
      ? 0
      : ((_scroll.offset - _headerExtent) / _rowExtent).floor().clamp(
          0,
          _lookup.state.items.length,
        );
  void _captureAnchor({double? extent, double? header}) {
    if (!_scroll.hasClients || _lookup.state.items.isEmpty) return;
    final row = extent ?? _rowExtent;
    final position = (_scroll.offset - (header ?? _headerExtent)) / row;
    if (position < 0) return;
    final index = position.floor().clamp(0, _lookup.state.items.length - 1);
    _anchor = (_lookup.state.items[index].key, position - index);
  }

  double? _correctLayout(double pixels) {
    final anchor = _anchor;
    _lastHeaderExtent = _headerExtent;
    if (anchor == null) return null;
    final index = _lookup.state.items.indexWhere(
      (item) => item.key == anchor.$1,
    );
    _anchor = null;
    if (index < 0) return null;
    return _lastHeaderExtent + (index + anchor.$2) * _rowExtent;
  }

  void _release(int removed) {
    _captureAnchor();
    final released = _lookup.state.items
        .take(removed)
        .map((item) => item.key)
        .toSet();
    if (released.any((key) => _rowFocus[key]?.hasFocus ?? false)) {
      final focus = _rowFocus[_anchor?.$1];
      if (focus != null && focus.context != null) {
        focus.requestFocus();
      } else {
        _headingFocus.requestFocus();
      }
    }
  }

  void _edited() {
    if (!_owns || _syncingQuery) return;
    final value = _query.value;
    _lookup.editQuery(
      value.text,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  void _scrolled() {
    if (!_owns ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    _lookup.setNearEnd(_scroll.position.extentAfter <= _rowExtent * 2);
  }

  void _layoutDone() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_owns) return;
      final retained = _lookup.state.items.map((item) => item.key).toSet();
      for (final key
          in _rowFocus.keys.where((key) => !retained.contains(key)).toList()) {
        _rowFocus.remove(key)?.dispose();
      }
      _scrolled();
    });
  }

  void _field(DocumentVocabularyField field) {
    if (!_owns || field == _lookup.state.field) return;
    _selectionNotice = null;
    _syncingQuery = true;
    _query.clear();
    _syncingQuery = false;
    unawaited(_lookup.selectField(field));
  }

  void _select(DocumentVocabularyOption option) {
    if (!_owns) return;
    final current = widget.documents.state;
    if (_lookup.state.field == DocumentVocabularyField.tag &&
        current.desiredCriteria.tags.length >= 20 &&
        !current.selectedTags.any((item) => item.key == option.key)) {
      setState(() => _selectionNotice = 'You can select up to 20 tags.');
      return;
    }
    if (_selectionNotice != null) setState(() => _selectionNotice = null);
    unawaited(widget.documents.selectOption(_lookup.state.field, option));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _query.dispose();
    _scroll.dispose();
    _headingFocus.dispose();
    for (final focus in _rowFocus.values) {
      focus.dispose();
    }
    unawaited(_lookup.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, _) => BlocBuilder<DocumentsCubit, DocumentsState>(
      bloc: widget.documents,
      builder: (context, documents) => BlocConsumer<DocumentVocabularyCubit, DocumentVocabularyState>(
        bloc: _lookup,
        listenWhen: (before, after) =>
            before.resetRevision != after.resetRevision,
        listener: (_, _) {
          _anchor = null;
          if (_scroll.hasClients) _scroll.jumpTo(0);
        },
        builder: (context, state) {
          if (_anchor == null && _lastHeaderExtent > 0) {
            _captureAnchor(header: _lastHeaderExtent);
          }
          final style = Theme.of(context).textTheme.bodyLarge!;
          final painter = TextPainter(
            text: TextSpan(text: 'Ag', style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final extent = math.max(64.0, painter.height * 2 + 20);
          painter.dispose();
          if (extent != _rowExtent) {
            if (_anchor == null) {
              _captureAnchor(extent: _rowExtent, header: _lastHeaderExtent);
            }
            _rowExtent = extent;
          }
          _layoutDone();
          final criteria = documents.desiredCriteria;
          final selectedKeys = switch (state.field) {
            DocumentVocabularyField.tag =>
              documents.selectedTags.map((option) => option.key).toSet(),
            DocumentVocabularyField.sender => {
              if (documents.selectedSender != null)
                documents.selectedSender!.key,
            },
            DocumentVocabularyField.recipient => {
              if (documents.selectedRecipient != null)
                documents.selectedRecipient!.key,
            },
          };
          final selectionNotice = criteria.tags.length >= 20
              ? _selectionNotice
              : null;
          final status =
              selectionNotice ??
              (state.blocked
                  ? 'Finish entering a valid lookup'
                  : state.error != null
                  ? 'Could not load options'
                  : state.loading
                  ? 'Loading options…'
                  : !state.loaded
                  ? 'Waiting for lookup…'
                  : state.items.isEmpty
                  ? DocumentUploadValidation.trim(state.rawQuery).isEmpty
                        ? 'No ${state.field == DocumentVocabularyField.tag ? 'tags' : '${state.field.name}s'} in this library yet'
                        : 'No matching values'
                  : state.released
                  ? 'Earlier options were released'
                  : state.nextCursor == null
                  ? 'All matching options are shown'
                  : 'Scroll for more options');
          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: selectionNotice == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Tooltip(
                                    message: selectionNotice,
                                    child: Semantics(
                                      key: const Key(
                                        'documentFilterSelectionNotice',
                                      ),
                                      liveRegion: true,
                                      label: selectionNotice,
                                      excludeSemantics: true,
                                      child: Text(
                                        '20 tags max',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        TextButton.icon(
                          key: const Key('closeDocumentFilters'),
                          onPressed: () {
                            if (_owns) widget.onClose();
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: CustomScrollView(
                      key: const Key('documentVocabularyScroll'),
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: _DocumentVocabularyHeader(
                            onExtent: (extent) => _headerExtent = extent,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Focus(
                                  focusNode: _headingFocus,
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      'Filter documents',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Changes apply immediately.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                DocumentKindFilters(
                                  kinds: criteria.kinds,
                                  keyPrefix: 'documentFilterType',
                                  onChanged: (kinds) async {
                                    if (_owns) {
                                      await widget.documents.setKinds(kinds);
                                    }
                                  },
                                ),
                                if (criteria.filterCount > 0) ...[
                                  const SizedBox(height: 8),
                                  DocumentActiveFilters(
                                    criteria: criteria,
                                    onRemoveTag: (tag) async {
                                      if (_owns) {
                                        await widget.documents.removeTag(tag);
                                      }
                                    },
                                    onClearAddress: (field) async {
                                      if (_owns) {
                                        await widget.documents.clearAddress(
                                          field,
                                        );
                                      }
                                    },
                                    onClearKinds: () async {
                                      if (_owns) {
                                        await widget.documents.clearKinds();
                                      }
                                    },
                                    onReset: () async {
                                      if (_owns) {
                                        await widget.documents.resetFilters();
                                      }
                                    },
                                  ),
                                ],
                                const AppStripedDivider(height: 24),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Tags and people',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final field
                                        in DocumentVocabularyField.values)
                                      ChoiceChip(
                                        key: Key(
                                          'documentFilter-${field.name}',
                                        ),
                                        label: Text(switch (field) {
                                          DocumentVocabularyField.tag => 'Tags',
                                          DocumentVocabularyField.sender =>
                                            'Sender',
                                          DocumentVocabularyField.recipient =>
                                            'Recipient',
                                        }),
                                        selected: state.field == field,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.padded,
                                        onSelected: (_) => _field(field),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  switch (state.field) {
                                    DocumentVocabularyField.tag => 'Matches documents with every selected tag',
                                    DocumentVocabularyField.sender =>
                                      'Matches the selected sender',
                                    DocumentVocabularyField.recipient =>
                                      'Includes To, CC and BCC',
                                  },
                                  key: const Key('documentFilterHelp'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const Key('documentVocabularyQuery'),
                                  controller: _query,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) {
                                    if (_owns) unawaited(_lookup.submit());
                                  },
                                  decoration: InputDecoration(
                                    labelText:
                                        'Search existing ${state.field == DocumentVocabularyField.tag ? 'tags' : '${state.field.name}s'}',
                                    errorText: state.validation,
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: IconButton(
                                      tooltip: 'Clear lookup',
                                      onPressed: () {
                                        if (_owns) _query.clear();
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                ),
                                if (state.field != DocumentVocabularyField.tag)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      key: const Key('anyDocumentAddress'),
                                      onPressed: () {
                                        if (_owns) {
                                          unawaited(
                                            widget.documents.clearAddress(
                                              state.field,
                                            ),
                                          );
                                        }
                                      },
                                      child: Text('Any ${state.field.name}'),
                                    ),
                                  ),
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(context)
                                              .scale(16) *
                                          3 +
                                      56,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(status, maxLines: 3),
                                      ),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Row(
                                            children: [
                                              if (state.error != null)
                                                TextButton(
                                                  onPressed: () {
                                                    if (_owns) {
                                                      unawaited(
                                                        _lookup.retry(),
                                                      );
                                                    }
                                                  },
                                                  child: const Text('Retry'),
                                                ),
                                              if (state.released ||
                                                  state.error != null)
                                                TextButton(
                                                  onPressed: () {
                                                    if (_owns) {
                                                      unawaited(
                                                        _lookup.restart(),
                                                      );
                                                    }
                                                  },
                                                  child: const Text(
                                                    'Restart list',
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 2,
                                        child: state.loading
                                            ? AppStripedProgressIndicator(
                                                minHeight: 2,
                                                animate:
                                                    !(MediaQuery.disableAnimationsOf(
                                                          context,
                                                        ) ||
                                                        View.of(context)
                                                            .platformDispatcher
                                                            .accessibilityFeatures
                                                            .reduceMotion),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverFixedExtentList(
                          itemExtent: _rowExtent,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final option = state.items[index];
                              final selected = selectedKeys.contains(
                                option.key,
                              );
                              final focus = _rowFocus.putIfAbsent(
                                option.key,
                                FocusNode.new,
                              );
                              return Tooltip(
                                key: ValueKey(option.key),
                                message: option.value,
                                child: Semantics(
                                  label: option.value,
                                  checked: selected,
                                  inMutuallyExclusiveGroup:
                                      state.field !=
                                      DocumentVocabularyField.tag,
                                  focusable: true,
                                  focused: focus.hasFocus,
                                  onTap: () => _select(option),
                                  excludeSemantics: true,
                                  child: InkWell(
                                    focusNode: focus,
                                    onFocusChange: (_) {
                                      if (mounted) setState(() {});
                                    },
                                    onTap: () => _select(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          ExcludeSemantics(
                                            child: Icon(
                                              state.field ==
                                                      DocumentVocabularyField
                                                          .tag
                                                  ? selected
                                                        ? Icons.check_box
                                                        : Icons
                                                              .check_box_outline_blank
                                                  : selected
                                                  ? Icons.radio_button_checked
                                                  : Icons
                                                        .radio_button_unchecked,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              option.value,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: style,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: state.items.length,
                            findChildIndexCallback: (key) =>
                                key is ValueKey<String>
                                ? _indexOf(state.items, key.value)
                                : null,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text(status),
                                ),
                                if (state.error != null)
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          if (_owns) unawaited(_lookup.retry());
                                        },
                                        child: const Text('Retry'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          if (_owns) {
                                            unawaited(_lookup.restart());
                                          }
                                        },
                                        child: const Text('Restart list'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  int? _indexOf(List<DocumentVocabularyOption> items, String key) {
    final index = items.indexWhere((item) => item.key == key);
    return index < 0 ? null : index;
  }
}

final class _DocumentVocabularyHeader extends SingleChildRenderObjectWidget {
  const _DocumentVocabularyHeader({
    required this.onExtent,
    required this.padding,
    required super.child,
  });

  final ValueChanged<double> onExtent;
  final EdgeInsets padding;

  @override
  _DocumentVocabularyHeaderRenderBox createRenderObject(BuildContext context) =>
      _DocumentVocabularyHeaderRenderBox(onExtent: onExtent, padding: padding);

  @override
  void updateRenderObject(
    BuildContext context,
    _DocumentVocabularyHeaderRenderBox renderObject,
  ) {
    renderObject
      ..onExtent = onExtent
      ..padding = padding;
  }
}

final class _DocumentVocabularyHeaderRenderBox extends RenderPadding {
  _DocumentVocabularyHeaderRenderBox({
    required this.onExtent,
    required super.padding,
  });

  ValueChanged<double> onExtent;

  @override
  void performLayout() {
    super.performLayout();
    onExtent(size.height);
  }
}

final class _DocumentVocabularyScrollController extends ScrollController {
  _DocumentVocabularyScrollController(this.correction);
  final double? Function(double) correction;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _DocumentVocabularyScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    correction: correction,
  );
}

final class _DocumentVocabularyScrollPosition
    extends ScrollPositionWithSingleContext {
  _DocumentVocabularyScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.correction,
  });
  final double? Function(double) correction;
  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final target = correction(pixels)?.clamp(minScrollExtent, maxScrollExtent);
    if (target != null && (target - pixels).abs() > .01) {
      correctPixels(target);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
