import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/app/client_errors.dart';

/// 1:1 port-тест `app/clientErrors.ts` (целевой путь таблицы:
/// test/app/client_errors_test.dart).
void main() {
  test('ResizeObserver loop → игнорируется', () {
    expect(
      isIgnorableClientError(
          'ResizeObserver loop completed with undelivered notifications'),
      isTrue,
    );
    expect(
        isIgnorableClientError('ResizeObserver loop limit exceeded'), isTrue);
  });

  test('прочие ошибки → не игнорируются', () {
    expect(isIgnorableClientError('TypeError: boom'), isFalse);
    expect(isIgnorableClientError(''), isFalse);
  });
}
