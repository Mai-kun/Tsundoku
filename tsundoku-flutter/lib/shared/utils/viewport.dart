/// 1:1 port of `mediatracker-ui/src/shared/utils/viewport.svelte.ts`.
///
/// Единый реактивный источник ширины окна. HomeView выводит из неё лимит
/// компактных секций (колонки × полные ряды), так что живой ресайз держит
/// колонки сетки и кнопку лимита в синхронизации без дублированных
/// слушателей в каждой вью. В Svelte ширина бралась из `window.innerWidth`
/// (resize-listener); в Flutter источником ширины является `MediaQuery`,
/// поэтому AppShell (Фаза 3) вызывает [ViewportController.update] на каждом
/// изменении размеров (решение #13).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `typeof window === "undefined" ? 1280 : window.innerWidth` — 1280 как
/// безопасный дефолт до первого MediaQuery-апдейта.
const double defaultViewportWidth = 1280;

class ViewportController extends Notifier<double> {
  @override
  double build() => defaultViewportWidth;

  /// Вызывается из AppShell на каждом MediaQuery-изменении ширины.
  void update(double width) {
    if (state != width) state = width;
  }
}

final viewportProvider =
    NotifierProvider<ViewportController, double>(ViewportController.new);

/// `windowWidth()` — чтение текущей ширины через provider.
double windowWidth(Ref ref) => ref.watch(viewportProvider);
