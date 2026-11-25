/// 1:1 port of `mediatracker-ui/src/shared/utils/swrCache.ts`.
///
/// Module-level snapshot cache for stale-while-revalidate views: a view
/// paints the previous payload instantly on mount and refetches in the
/// background. Keyed, so one cache holds every tab (per category on the
/// library screen).
library;

/// `interface SwrCache<T>` — peek/set/invalidate.
class SwrCache<T> {
  final Map<String, T> _entries = <String, T>{};

  /// Last known payload for `key`, or null when the view has never loaded.
  T? peek(String key) => _entries[key];

  void set(String key, T value) {
    _entries[key] = value;
  }

  void invalidate(String key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }
}

/// `createSwrCache<T>()` — тот же API именованным конструктором.
SwrCache<T> createSwrCache<T>() => SwrCache<T>();
