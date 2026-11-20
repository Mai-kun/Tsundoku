/// 1:1 port of `mediatracker-ui/src/shared/utils/perfMarks.ts`.
///
/// Web `performance.mark/measure` → переносимый [Stopwatch]-реестр
/// (работает на всех платформах и в тестах; решение #11). Данные доступны
/// через [tsundokuPerf] — аналог `window.__tsundokuPerf`.
library;

final Map<String, double> tsundokuPerf = <String, double>{};
final Map<String, Stopwatch> _watches = <String, Stopwatch>{};

void markStart(String name) {
  final watch = _watches[name] ??= Stopwatch();
  watch
    ..reset()
    ..start();
}

/// Останавливает замер, сохраняет длительность (мс) в [tsundokuPerf] и
/// возвращает её (или null, если start не вызывался).
double? markEnd(String name) {
  final watch = _watches[name];
  if (watch == null) return null;
  watch.stop();
  final duration = watch.elapsedMicroseconds / 1000.0;
  tsundokuPerf[name] = duration;
  return duration;
}
