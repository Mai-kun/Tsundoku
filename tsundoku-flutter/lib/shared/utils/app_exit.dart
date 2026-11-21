/// 1:1 port of `mediatracker-ui/src/shared/utils/appExit.ts`.
///
/// window.close()/document.body.innerHTML — браузерные API; в Flutter они
/// заменяются инъекцией колбеков (закрытие окна — window_manager/трей за
/// платформенным фасадом, «stopped screen» — экран-заглушка AppShell;
/// решение #13). Логика и тайминги (400ms) сохранены 1-в-1.
library;

import 'dart:async';

import '../i18n/index.dart';
import '../api/api.dart';

/// «Экран остановки», показываемый когда браузер/платформа отказался
/// закрывать окно: заголовок и описание из i18n (closeAppModal).
class StoppedScreenText {
  final String title;
  final String description;
  const StoppedScreenText({required this.title, required this.description});
}

class AppExit {
  final TsundokuApi api;

  AppExit(this.api);

  /* window.close() only works for windows the browser lets script close.
     When it refuses (Zen/Firefox tab opened by the user), show a stopped
     screen instead. */
  Future<void> exitApp({
    required Future<void> Function() closeWindow,
    required void Function(StoppedScreenText text) showStoppedScreen,
    /// Аналог проверки `window.closed` через 400ms: если окно закрылось —
    /// stopped screen не нужен. В приложении — PlatformService-фасад.
    bool Function()? isWindowClosed,
    Locale locale = Locale.ru,
  }) async {
    try {
      await api.shutdownApp();
    } catch (_) {
      // The server may already be down; still close the window.
    }
    await closeWindow();
    Timer(const Duration(milliseconds: 400), () {
      final closed = isWindowClosed?.call() ?? false;
      if (!closed) {
        showStoppedScreen(StoppedScreenText(
          title: I18nDictionary(locale).tr('closeAppModal.stoppedTitle'),
          description:
              I18nDictionary(locale).tr('closeAppModal.stoppedDescription'),
        ));
      }
    });
  }

  void closeToTray({
    required Future<void> Function() closeWindow,
    required void Function({required String title, required String description})
        showToast,
    bool Function()? isWindowClosed,
    Locale locale = Locale.ru,
  }) {
    closeWindow();
    Timer(const Duration(milliseconds: 400), () {
      final closed = isWindowClosed?.call() ?? false;
      if (!closed) {
        final dict = I18nDictionary(locale);
        showToast(
          title: dict.tr('closeAppModal.backgroundToast'),
          description: dict.tr('toast.descActionDone'),
        );
      }
    });
  }
}
