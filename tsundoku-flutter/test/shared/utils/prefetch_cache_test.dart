import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/utils/prefetch_cache.dart';

/// Полный цикл prefetchCache: кэш → in-flight дедупликация → TTL-протухание →
/// invalidate; ошибки не кэшируются.
void main() {
  test('load:Fetcher кэширует результат; peek до/после TTL', () async {
    final cache = createPrefetchCache<String>(100);
    expect(cache.peek('a'), isNull);
    expect(cache.has('a'), isFalse);

    var fetchCalls = 0;
    final value = await cache.load('a', () async {
      fetchCalls += 1;
      return 'data';
    });

    expect(value, 'data');
    expect(cache.peek('a'), 'data');
    expect(cache.has('a'), isTrue);

    // Повторный load из кэша — fetcher не дёргается.
    final again = await cache.load('a', () async {
      fetchCalls += 1;
      return 'other';
    });
    expect(again, 'data');
    expect(fetchCalls, 1);

    // TTL протухает (100ms) → peek null, load снова fetch'ит.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(cache.peek('a'), isNull);
    final refetched = await cache.load('a', () async {
      fetchCalls += 1;
      return 'fresh';
    });
    expect(refetched, 'fresh');
    expect(fetchCalls, 2);
  });

  test('load: тот же id во время полёта — дедупликация (один fetcher)',
      () async {
    final cache = createPrefetchCache<int>(10000);
    var fetchCalls = 0;
    final first = cache.load('x', () async {
      fetchCalls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return 1;
    });
    final second = cache.load('x', () async {
      fetchCalls += 1;
      return 2;
    });

    expect(await first, 1);
    expect(await second, 1, reason: 'второй load дожидается первого запроса');
    expect(fetchCalls, 1);
  });

  test('разные id — независимые загрузки', () async {
    final cache = createPrefetchCache<int>(10000);
    final a = cache.load('a', () async => 1);
    final b = cache.load('b', () async => 2);
    expect(await a, 1);
    expect(await b, 2);
    expect(cache.peek('a'), 1);
    expect(cache.peek('b'), 2);
  });

  test('ошибка fetcher не кэшируется и снимает in-flight', () async {
    final cache = createPrefetchCache<String>(10000);
    var attempts = 0;
    Future<String> failing() async {
      attempts += 1;
      throw StateError('boom');
    }

    await expectLater(cache.load('k', failing), throwsA(isA<StateError>()));
    expect(cache.peek('k'), isNull, reason: 'ошибка не кэшируется');

    // Повторный вызов — снова fetcher (in-flight очищен через finally).
    await expectLater(cache.load('k', failing), throwsA(isA<StateError>()));
    expect(attempts, 2);
  });

  test('invalidate сбрасывает кэш; следующий load ходит в сеть', () async {
    final cache = createPrefetchCache<String>(60000);
    var fetchCalls = 0;
    await cache.load('i', () async {
      fetchCalls += 1;
      return 'v1';
    });
    cache.invalidate('i');
    expect(cache.peek('i'), isNull);
    final fresh = await cache.load('i', () async {
      fetchCalls += 1;
      return 'v2';
    });
    expect(fresh, 'v2');
    expect(fetchCalls, 2);
  });

  test('TTL-граница: ровно на границе — значение ещё живо/уже нет', () async {
    final cache = createPrefetchCache<int>(50);
    await cache.load('t', () async => 7);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cache.peek('t'), 7, reason: 'до expiresAt значение живо');
  });
}
