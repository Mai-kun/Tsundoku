/// 1:1 port of `mediatracker-ui/src/shared/utils/prefetchCache.ts`.
library;

/// `interface PrefetchCache<T>` — peek/has/load/invalidate.
abstract class PrefetchCache<T> {
  /// Fresh value for `id`, or null when absent/expired. Never triggers a
  /// fetch.
  T? peek(String id);

  bool has(String id);

  /// Returns the cached value, an already in-flight request for the same
  /// `id`, or starts `fetcher` and caches its result. Failures are not
  /// cached.
  Future<T> load(String id, Future<T> Function() fetcher);

  /// Overwrites the cached value for `key` (optimistic patch).
  void set(String key, T value);

  void invalidate(String id);

  void clear();
}

class _PrefetchCacheImpl<T> implements PrefetchCache<T> {
  final int ttlMs;
  final Map<String, ({T value, DateTime expiresAt})> _entries = {};
  final Map<String, Future<T>> _inFlight = {};

  _PrefetchCacheImpl(this.ttlMs);

  @override
  T? peek(String id) {
    final entry = _entries[id];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _entries.remove(id);
      return null;
    }
    return entry.value;
  }

  @override
  bool has(String id) => peek(id) != null;

  @override
  Future<T> load(String id, Future<T> Function() fetcher) {
    final cached = peek(id);
    if (cached != null) return Future<T>.value(cached);

    final running = _inFlight[id];
    if (running != null) return running;

    final request = fetcher().then<T>((value) {
      _entries[id] = (
        value: value,
        expiresAt: DateTime.now().add(Duration(milliseconds: ttlMs)),
      );
      return value;
    }).whenComplete(() {
      _inFlight.remove(id);
    });

    _inFlight[id] = request;
    return request;
  }

  @override
  void set(String key, T value) {
    // Мутация in-place в TS не трогает TTL существующей записи.
    final existing = _entries[key];
    _entries[key] = (
      value: value,
      expiresAt: existing?.expiresAt ??
          DateTime.now().add(Duration(milliseconds: ttlMs)),
    );
  }

  @override
  void invalidate(String id) {
    _entries.remove(id);
  }

  @override
  void clear() {
    _entries.clear();
  }
}

/// `createPrefetchCache<T>(ttlMs)`.
PrefetchCache<T> createPrefetchCache<T>(int ttlMs) =>
    _PrefetchCacheImpl<T>(ttlMs);
