import 'package:flutter/material.dart';

import 'vennuzo_theme.dart';

extension VennuzoThemeX on BuildContext {
  VennuzoPalette get palette => Theme.of(this).extension<VennuzoPalette>()!;

  TextTheme get text => Theme.of(this).textTheme;
}
