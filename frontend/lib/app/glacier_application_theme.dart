import 'package:flutter/material.dart';

import '../ui/domabas_ui.dart';

Widget glacierApplicationTheme(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  final mobile =
      MediaQuery.sizeOf(context).width < 800 ||
      theme.platform == TargetPlatform.android ||
      theme.platform == TargetPlatform.iOS;
  return mobile ? Theme(data: glacierMobileTheme(theme), child: child) : child;
}
