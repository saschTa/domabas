import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../../../ui/glacier.dart';
import '../cubits/documents_cubit.dart';
import 'document_search_dialog.dart';
import 'document_search_widgets.dart';

final class DocumentsWorkspaceToolbar extends StatefulWidget {
  const DocumentsWorkspaceToolbar({
    super.key,
    required this.cubit,
    this.vocabulary,
    this.libraryPicker,
    this.workspaceActions,
    this.libraryName = '',
    this.showSearchButton = false,
  });
  final DocumentsCubit cubit;
  final DocumentVocabularyRepository? vocabulary;
  final Widget? libraryPicker, workspaceActions;
  final String libraryName;
  final bool showSearchButton;
  @override
  DocumentsWorkspaceToolbarState createState() =>
      DocumentsWorkspaceToolbarState();
}

final class DocumentsWorkspaceToolbarState
    extends State<DocumentsWorkspaceToolbar> {
  final _filtersFocus = FocusNode();
  RawDialogRoute<void>? _searchRoute;
  NavigatorState? _searchNavigator;
  int _searchGeneration = 0;

  @override
  void didUpdateWidget(DocumentsWorkspaceToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit ||
        oldWidget.vocabulary != widget.vocabulary) {
      _dismissSearch();
    }
  }

  @override
  void dispose() {
    _dismissSearch();
    _filtersFocus.dispose();
    super.dispose();
  }

  void _dismissSearch() {
    _searchGeneration++;
    final route = _searchRoute;
    final navigator = _searchNavigator;
    _searchRoute = null;
    _searchNavigator = null;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
  }

  Future<void> openSearch() async {
    final owner = widget.cubit;
    if (_searchRoute != null ||
        owner.isClosed ||
        !owner.capabilities.read ||
        !owner.capabilities.search ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final repository = widget.vocabulary;
    final generation = ++_searchGeneration;
    final navigator = _searchNavigator = Navigator.of(context);
    final native = GlacierNativePresentationScope.maybeOf(context);
    final returnFocus = FocusManager.instance.primaryFocus;
    late final RawDialogRoute<void> route;
    bool owns() =>
        mounted &&
        identical(owner, widget.cubit) &&
        identical(repository, widget.vocabulary) &&
        !owner.isClosed &&
        generation == _searchGeneration &&
        _searchRoute == route &&
        navigator.mounted &&
        route.navigator == navigator &&
        route.isCurrent;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: native == null ? Colors.black26 : Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (routeContext, _, _) => glacierDialogBackdrop(
        routeContext,
        (_) => SafeArea(
          child: DocumentSearchDialog(
            documents: owner,
            vocabulary: repository,
            libraryName: widget.libraryName,
            isCurrent: owns,
            onCancel: () {
              if (owns()) navigator.pop();
            },
            onApply: (draft) {
              if (!owns()) return;
              unawaited(
                owner.applySearch(
                  draft.desiredCriteria,
                  selectedTags: draft.selectedTags,
                  selectedSender: draft.selectedSender,
                  selectedRecipient: draft.selectedRecipient,
                  replaceSelections: true,
                ),
              );
              navigator.pop();
            },
          ),
        ),
        native: native,
      ),
    );
    _searchRoute = route;
    await navigator.push(route);
    if (!mounted || generation != _searchGeneration || _searchRoute != route) {
      return;
    }
    _searchRoute = null;
    _searchNavigator = null;
    if (returnFocus?.context != null && returnFocus!.canRequestFocus) {
      returnFocus.requestFocus();
    } else if (_filtersFocus.canRequestFocus) {
      _filtersFocus.requestFocus();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DocumentsCubit, DocumentsState>(
    bloc: widget.cubit,
    builder: (context, state) {
      final canSearch =
          widget.cubit.capabilities.read && widget.cubit.capabilities.search;
      return GlacierToolbar(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.showSearchButton && canSearch)
                GlacierButton(
                  label: 'Search documents',
                  icon: Icons.search,
                  onPressed: openSearch,
                ),
              if (canSearch) ...[
                DocumentKindFilters(
                  kinds: state.desiredCriteria.kinds,
                  onChanged: widget.cubit.setKinds,
                  compact: true,
                ),
                GlacierButton(
                  focusNode: _filtersFocus,
                  key: const Key('documentFilters'),
                  icon: Icons.tune,
                  onPressed: openSearch,
                  label: state.desiredCriteria.filterCount == 0
                      ? 'Filters'
                      : 'Filters (${state.desiredCriteria.filterCount})',
                ),
                DocumentSortControl(
                  criteria: state.desiredCriteria,
                  onSort: widget.cubit.setSort,
                  compact: MediaQuery.sizeOf(context).width < 600,
                ),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final layout in DocumentLayout.values)
                    Semantics(
                      selected: state.layout == layout,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: state.layout == layout
                              ? GlacierTokens.of(context).accent
                                    .withValues(alpha: .12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: GlacierIconButton(
                          label: layout == DocumentLayout.grid
                              ? 'Grid'
                              : 'List',
                          icon: layout == DocumentLayout.grid
                              ? Icons.grid_view_rounded
                              : Icons.view_list_rounded,
                          onPressed: () => widget.cubit.setLayout(layout),
                        ),
                      ),
                    ),
                ],
              ),
              if (state.error != null)
                GlacierIconButton(
                  key: const Key('retryDocuments'),
                  label: 'Retry',
                  icon: Icons.refresh,
                  onPressed:
                      state.isSaving || state.intentBlocked || state.showLoading
                      ? null
                      : widget.cubit.retryCollection,
                ),
              ?widget.workspaceActions,
              ?widget.libraryPicker,
            ],
          ),
        ],
      );
    },
  );
}
