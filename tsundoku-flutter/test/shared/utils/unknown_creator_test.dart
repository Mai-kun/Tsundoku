import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/utils/unknown_creator.dart';

/// 1:1 port-тест `unknownCreator.ts`.
void main() {

    test('null/пустая строка → true', () {
      expect(isUnknownCreatorName(null), isTrue);
      expect(isUnknownCreatorName(''), isTrue);
    });

    test('плейсхолдеры 1-в-1 (trim + lowercase)', () {
      expect(isUnknownCreatorName('-'), isTrue);
      expect(isUnknownCreatorName('--'), isTrue);
      expect(isUnknownCreatorName('—'), isTrue);
      expect(isUnknownCreatorName('n/a'), isTrue);
      expect(isUnknownCreatorName('N/A'), isTrue);
      expect(isUnknownCreatorName('unknown'), isTrue);
      expect(isUnknownCreatorName(' Unknown '), isTrue);
      expect(isUnknownCreatorName('Unknown Author'), isTrue);
      expect(isUnknownCreatorName('неизвестный автор'), isTrue);
      expect(isUnknownCreatorName('Неизвестный Автор'), isTrue);
    });

    test('реальные авторы → false', () {
      expect(isUnknownCreatorName('Frank Herbert'), isFalse);
      expect(isUnknownCreatorName('Урасава Наоки'), isFalse);
      expect(isUnknownCreatorName('Team Cherry'), isFalse);
    });}
