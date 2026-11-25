/// Кроссплатформенный встроенный плеер YouTube-трейлера:
/// - `dart.library.io` (Linux/Windows): `media_kit` + `youtube_explode_dart`
/// - `dart.library.js_interop` (Web/wasm): `<iframe>` (`youtube-nocookie.com`)
/// - default: заглушка с открытием во внешнем браузере.
library;

export 'trailer_player_stub.dart'
    if (dart.library.js_interop) 'trailer_player_web.dart'
    if (dart.library.io) 'trailer_player_io.dart';
