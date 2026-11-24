import 'package:material_ui/material_ui.dart';

/// Web / Release-заглушка для debug-инструментов (без `dart:io`, `marionette_flutter`
/// и `flutter_agentation`).
void ensureAppBindingInitialized() {
  WidgetsFlutterBinding.ensureInitialized();
}

/// Возвращает `null` на Web / non-io платформах (без оверхеда).
TransitionBuilder? buildDebugAgentationOverlay({bool mcpEnabled = true}) {
  return null;
}
