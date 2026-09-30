import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final class ScanImage extends StatefulWidget {
  const ScanImage({
    super.key,
    required this.bytes,
    required this.fit,
    this.semanticLabel,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final String? semanticLabel;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<ScanImage> createState() => _ScanImageState();
}

final class _ScanImageState extends State<ScanImage> {
  late MemoryImage _image;

  @override
  void initState() {
    super.initState();
    _image = MemoryImage(Uint8List.fromList(widget.bytes));
  }

  @override
  void didUpdateWidget(ScanImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) &&
        !listEquals(oldWidget.bytes, widget.bytes)) {
      _image = MemoryImage(Uint8List.fromList(widget.bytes));
    }
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _image,
    fit: widget.fit,
    gaplessPlayback: true,
    semanticLabel: widget.semanticLabel,
    errorBuilder: widget.errorBuilder,
  );
}
