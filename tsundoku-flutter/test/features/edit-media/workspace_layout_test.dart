import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_layout.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('clampWindowRect', () {
    test('размер клампится в видимую полосу (margin 16, topbar 64)', () {
      final rect = clampWindowRect(
        const WorkspaceRect(x: -100, y: -100, w: 5000, h: 5000),
        'main',
        1440,
        900,
      );
      expect(rect.w, 1440 - 2 * kSideMargin); // 1408
      expect(rect.h, 900 - kTopBar - kBottomMargin); // 820
      expect(rect.x, kSideMargin);
      expect(rect.y, kTopBar);
    });

    test('меньше минимума — приподнимается до min', () {
      final rect = clampWindowRect(
        const WorkspaceRect(x: 100, y: 100, w: 10, h: 10),
        'alt',
        1440,
        900,
      );
      expect(rect.w, 280);
      expect(rect.h, 180);
    });

    test('x вне вьюпорта справа — прижимается к правому краю', () {
      final rect = clampWindowRect(
        const WorkspaceRect(x: 2000, y: 100, w: 300, h: 200),
        'quotes',
        1440,
        900,
      );
      expect(rect.x, 1440 - kSideMargin - rect.w);
      expect(rect.x + rect.w, 1440 - kSideMargin);
    });

    test('узкий вьюпорт: полоса меньше минимума — окно в полосе (ниже min)', () {
      final rect = clampWindowRect(
        const WorkspaceRect(x: 0, y: 0, w: 800, h: 800),
        'main',
        300,
        300,
      );
      // max(полоса, min) — не ниже min (позиция при этом всё равно в полосе).
      expect(rect.w, 380.0);
      expect(rect.h, 320.0);
      expect(rect.x, kSideMargin); // max(300-16-380, 16) = 16
      expect(rect.y, kTopBar);
    });
  });

  group('clampPoint', () {
    test('cover-точка клампится в полосу', () {
      final p = clampPoint(const OffsetPoint(-50, -50), 1440, 900);
      expect(p.x, kSideMargin);
      expect(p.y, kTopBar);
      final q = clampPoint(const OffsetPoint(5000, 5000), 1440, 900);
      expect(q.x, 1440 - kSideMargin - kCoverSize.w);
      expect(q.y, 900 - kBottomMargin - kCoverSize.h);
    });
  });

  group('defaultLayout', () {
    test('пять окон + cover; колонки внутри вьюпорта', () {
      final layout = defaultLayout(1440, 900);
      expect(layout.windows.keys.toSet(), kWorkspaceWindowIds.toSet());
      for (final e in layout.windows.entries) {
        expect(e.value.x, greaterThanOrEqualTo(kSideMargin), reason: e.key);
        expect(e.value.y, greaterThanOrEqualTo(kTopBar), reason: e.key);
        expect(e.value.x + e.value.w,
            lessThanOrEqualTo(1440 - kSideMargin), reason: e.key);
        expect(e.value.y + e.value.h,
            lessThanOrEqualTo(900 - kBottomMargin), reason: e.key);
      }
      // Cover в центральной колонке.
      expect(layout.cover.x + kCoverSize.w / 2, closeTo(720, 0.5));
    });

    test('композиция: main над quotes слева, notes над images справа', () {
      final layout = defaultLayout(1440, 900);
      final main = layout.windows['main']!;
      final quotes = layout.windows['quotes']!;
      final notes = layout.windows['notes']!;
      final images = layout.windows['images']!;
      final alt = layout.windows['alt']!;
      // main выше quotes, notes выше images.
      expect(main.y, lessThan(quotes.y));
      expect(main.x, lessThan(alt.x));
      expect(notes.x, greaterThan(alt.x));
      expect(notes.y, lessThan(images.y));
      // Центральная колонка: alt над cover.
      expect(alt.y + alt.h, lessThan(layout.cover.y));
    });
  });

  group('loadLayout/saveLayout', () {
    test('без сохранённой раскладки — дефолт', () async {
      final layout = await loadLayout(1440, 900);
      expect(layout.windows, defaultLayout(1440, 900).windows);
      expect(layout.cover, defaultLayout(1440, 900).cover);
    });

    test('сохранённая раскладка мержится и клампится', () async {
      final original = defaultLayout(1440, 900);
      final moved = WorkspaceLayout(
        cover: const OffsetPoint(500, 500),
        windows: {
          ...original.windows,
          'main': const WorkspaceRect(x: 3000, y: 3000, w: 900, h: 900),
        },
      );
      await saveLayout(moved);

      final loaded = await loadLayout(1440, 900);
      // Cover сохранён, окна клампнуты в вьюпорт.
      expect(loaded.cover, const OffsetPoint(500, 500));
      expect(loaded.windows['main']!.x,
          1440 - kSideMargin - loaded.windows['main']!.w);
      // Не сохранённые окна — дефолт.
      expect(loaded.windows['alt'], original.windows['alt']);
    });

    test('битый JSON — дефолт (без исключения)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kEditWorkspaceStorageKey, 'not-json{{');
      final layout = await loadLayout(1440, 900);
      expect(layout.windows, defaultLayout(1440, 900).windows);
    });
  });
}
