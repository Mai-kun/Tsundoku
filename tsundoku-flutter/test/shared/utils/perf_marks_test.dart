import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/utils/perf_marks.dart';

/// 1:1 port-тест `perfMarks.ts` (Performance API → Stopwatch, решение #11).
void main() {
  test('markStart/markEnd: длительность ≥ 0 и сохраняется в реестре', () {
    markStart('op');
    final duration = markEnd('op');
    expect(duration, isNotNull);
    expect(duration! >= 0, isTrue);
    expect(tsundokuPerf['op'], duration);
  });

  test('markEnd без start → null', () {
    expect(markEnd('never-started'), isNull);
  });

  test('повторный start сбрасывает замер', () {
    markStart('x');
    markStart('x');
    final d = markEnd('x');
    expect(d, isNotNull);
    expect(d! < 1000, isTrue, reason: 'после reset длительность близка к нулю');
  });

  test('независимые имена', () {
    markStart('a');
    expect(markEnd('b'), isNull);
    expect(markEnd('a'), isNotNull);
  });
}
