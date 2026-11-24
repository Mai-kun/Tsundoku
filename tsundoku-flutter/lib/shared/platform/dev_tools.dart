/// Условная изоляция debug-инструментов (`marionette_flutter`, `flutter_agentation`)
/// за платформенным фасадом (§1.3).
///
/// - `dart.library.io` (Linux/Windows/macOS/Android) → `dev_tools_io.dart`
///   (активируется только при `kDebugMode`).
/// - `dart.library.js_interop` / прочие (Web WASM) → `dev_tools_stub.dart`
///   (нулевой оверхед и 0 импортов `dart:io` / devtools-пакетов).
library;

export 'dev_tools_stub.dart'
    if (dart.library.io) 'dev_tools_io.dart';
