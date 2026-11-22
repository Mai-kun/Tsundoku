/// Точка входа платформенного фасада (§1.3): условный экспорт имплементации.
///
/// - `dart.library.io` — Linux/Windows/Android (platform_service_io.dart);
/// - `dart.library.js_interop` — Web/wasm (platform_service_web.dart);
/// - default — заглушка (не встречается на поддерживаемых целях).
library;

export 'platform_service.dart';
export 'drop_zone.dart';
export 'platform_service_stub.dart'
    if (dart.library.js_interop) 'platform_service_web.dart'
    if (dart.library.io) 'platform_service_io.dart';
