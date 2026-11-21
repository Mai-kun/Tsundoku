import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/detailed_score.dart';

/// Прямой перенос vitest-кейсов `detailedScore.test.ts` + ключевые ветки.
void main() {
  test('parseDetailedScore: валидный JSON с известными ключами', () {
    final map = parseDetailedScore(jsonEncode({
      'story': 9,
      'visuals': 7,
      'gameplay': 8.4,
    }));
    expect(map, {'story': 9, 'visuals': 7, 'gameplay': 8});
    // 8.4 округляется до 8 (1-в-1 Math.round):
    expect(map['gameplay'], 8);
  });

  test('parseDetailedScore: вне диапазона 1..10 отбрасывается', () {
    final map = parseDetailedScore(jsonEncode({'story': 0, 'visuals': 11}));
    expect(map, isEmpty);
  });

  test('parseDetailedScore: неизвестные ключи игнорируются', () {
    final map = parseDetailedScore(jsonEncode({'story': 5, 'style': 9}));
    expect(map, {'story': 5});
  });

  test('parseDetailedScore: мусор/массив/пусто → пустая карта', () {
    expect(parseDetailedScore(null), isEmpty);
    expect(parseDetailedScore(''), isEmpty);
    expect(parseDetailedScore('not json'), isEmpty);
    expect(parseDetailedScore(jsonEncode([1, 2])), isEmpty);
    expect(parseDetailedScore(jsonEncode(null)), isEmpty);
  });

  test('serializeDetailedScore: round-trip и null для пустых', () {
    const map = {'story': 9, 'visuals': 7};
    final json = serializeDetailedScore(map);
    expect(parseDetailedScore(json), map);

    expect(serializeDetailedScore(const {}), isNull);
    // Вне диапазона — всё отфильтровано → null:
    expect(serializeDetailedScore({'story': 0}), isNull);
  });

  test('getCriteriaAxes: game/book/manga/экранные 1-в-1', () {
    expect(getCriteriaAxes('game').map((a) => a.key).toList(),
        ['gameplay', 'story', 'visuals', 'sound', 'enjoyment']);
    expect(getCriteriaAxes('book').map((a) => a.key).toList(),
        ['story', 'characters', 'writing', 'pacing', 'enjoyment']);
    expect(getCriteriaAxes('manga').map((a) => a.key).toList(),
        ['story', 'visuals', 'characters', 'pacing', 'enjoyment']);
    // movie/tvshow/anime → SCREEN_AXES:
    expect(getCriteriaAxes('movie').map((a) => a.key).toList(),
        ['story', 'visuals', 'characters', 'sound', 'pacing']);
    expect(getCriteriaAxes('tvshow'), getCriteriaAxes('movie'));
    expect(getCriteriaAxes('anime'), getCriteriaAxes('movie'));
    expect(getCriteriaAxes(''), getCriteriaAxes('movie'));
  });

  test('CriterionAxis.label ru/en', () {
    final axis = getCriteriaAxes('game').first;
    expect(axis.label('ru'), 'Геймплей');
    expect(axis.label('en'), 'Gameplay');
  });

  test('computeDetailedAverage: exact/rounded/count', () {
    final avg = computeDetailedAverage({'story': 9, 'visuals': 7})!;
    expect(avg.count, 2);
    expect(avg.exact, 8.0);
    expect(avg.rounded, 8);

    final avg2 = computeDetailedAverage({'story': 8, 'visuals': 9, 'pacing': 9})!;
    expect(avg2.count, 3);
    expect(avg2.exact, 8.7);
    expect(avg2.rounded, 9);
  });

  test('computeDetailedAverage: пустая карта → null; кламп 1..10', () {
    expect(computeDetailedAverage(const {}), isNull);
    // Одиночное значение клампится 1..10:
    expect(computeDetailedAverage({'story': 1})!.rounded, 1);
    expect(computeDetailedAverage({'story': 10})!.rounded, 10);
  });

  test('isCriterionKey и criterionKeys 1-в-1', () {
    expect(isCriterionKey('story'), isTrue);
    expect(isCriterionKey('gameplay'), isTrue);
    expect(isCriterionKey('style'), isFalse);
    expect(criterionKeys.length, 8);
  });
}
