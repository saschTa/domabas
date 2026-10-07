import 'package:flutter/material.dart';

final class AppPagedList extends StatefulWidget {
  const AppPagedList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.pageSize = 20,
    this.hasMore = false,
    this.loading = false,
    this.onLoadMore,
    this.loadMoreLabel = 'Load more',
    this.loadMoreKey,
    this.footer,
  });

  final int itemCount, pageSize;
  final IndexedWidgetBuilder itemBuilder;
  final bool hasMore, loading;
  final VoidCallback? onLoadMore;
  final String loadMoreLabel;
  final Key? loadMoreKey;
  final Widget? footer;

  @override
  State<AppPagedList> createState() => _AppPagedListState();
}

final class _AppPagedListState extends State<AppPagedList> {
  final _top = GlobalKey();
  int _page = 0;
  int? _requestedPage;
  bool _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final saved = PageStorage.maybeOf(context)
        ?.readState(context, identifier: widget.key);
    if (widget.key != null && saved is int) _page = saved;
  }

  @override
  void didUpdateWidget(AppPagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_requestedPage case final target? when !widget.loading) {
      if (widget.itemCount > target * widget.pageSize && target != _page) {
        _page = target;
        _showFirstRow();
      }
      _requestedPage = null;
      _remember();
    }
  }

  void _remember() {
    if (widget.key != null) {
      PageStorage.maybeOf(context)
          ?.writeState(context, _page, identifier: widget.key);
    }
  }

  void _showFirstRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_top.currentContext case final context? when mounted) {
        Scrollable.ensureVisible(context, alignment: 0);
      }
    });
  }

  void _next() {
    final end = (_page + 1) * widget.pageSize;
    if (widget.itemCount > end) {
      setState(() => _page++);
      _remember();
      _showFirstRow();
    } else if (widget.hasMore && widget.onLoadMore != null) {
      _requestedPage = widget.itemCount < end ? _page : _page + 1;
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastPage = widget.itemCount == 0
        ? 0
        : (widget.itemCount - 1) ~/ widget.pageSize;
    _page = _page.clamp(0, lastPage);
    final start = _page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, widget.itemCount);
    final loadedNext = end < widget.itemCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(key: _top),
        for (var i = start; i < end; i++) widget.itemBuilder(context, i),
        ?widget.footer,
        if (widget.itemCount > widget.pageSize || widget.hasMore)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _page == 0 || widget.loading
                    ? null
                    : () {
                        setState(() => _page--);
                        _remember();
                        _showFirstRow();
                      },
                child: const Text('Previous'),
              ),
              Text(
                widget.itemCount == 0
                    ? 'No matching records loaded'
                    : '${start + 1}–$end',
              ),
              TextButton(
                key: widget.loadMoreKey,
                onPressed: widget.loading || (!loadedNext && !widget.hasMore)
                    ? null
                    : _next,
                child: Text(loadedNext ? 'Next' : widget.loadMoreLabel),
              ),
            ],
          ),
      ],
    );
  }
}
