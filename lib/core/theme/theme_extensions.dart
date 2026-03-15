import 'package:flutter/material.dart';

import 'eventora_theme.dart';

extension EventoraThemeX on BuildContext {
  EventoraPalette get palette => Theme.of(this).extension<EventoraPalette>()!;

  TextTheme get text => Theme.of(this).textTheme;
}
