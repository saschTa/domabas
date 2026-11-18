import 'package:flutter/material.dart';

final class CatalogFrame extends StatelessWidget {
  const CatalogFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.maxWidth = 960,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: padding,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    ),
  );
}
