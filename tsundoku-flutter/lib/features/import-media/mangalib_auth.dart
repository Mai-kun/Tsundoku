/// 1:1 port of `mediatracker-ui/src/features/import-media/mangalibAuth.svelte.ts`.
///
/// MangaLib (SocialLib) auth state, shared by the import panel and the
/// settings sources tab. The Bearer token is picked up from the user's own
/// browser session (server-side detector, `detect-token` endpoint), persisted
/// through the encrypted source-key storage and never kept in the frontend;
/// only the non-secret User ID lives in persisted storage for one-click
/// imports.
///
/// $state → Riverpod; localStorage → shared_preferences; showToast — инъекция
/// (решение #15: реальный toast подключается в Фазе 1).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';

const String userIdKey = 'mangalib_user_id';

@immutable
class MangalibAuthState {
  final bool checking;
  final bool connected;
  final String? maskedKey;
  final String userId;

  const MangalibAuthState({
    this.checking = true,
    this.connected = false,
    this.maskedKey,
    this.userId = '',
  });

  MangalibAuthState copyWith({
    bool? checking,
    bool? connected,
    String? maskedKey,
    String? userId,
  }) =>
      MangalibAuthState(
        checking: checking ?? this.checking,
        connected: connected ?? this.connected,
        maskedKey: maskedKey ?? this.maskedKey,
        userId: userId ?? this.userId,
      );
}

typedef MangalibToastFn = void Function({
  required String title,
  required String description,
  String type,
});

class MangalibAuthController extends Notifier<MangalibAuthState> {
  MangalibToastFn showToast = ({required title, required description, type = 'info'}) {};

  @override
  MangalibAuthState build() => const MangalibAuthState(checking: true);

  Future<String> readStoredMangalibUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(userIdKey)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> refreshMangalibAuth() => readMangalibStatus();

  /// Reads the server-side key status.
  Future<void> readMangalibStatus() async {
    try {
      final status = await ref.read(apiClientProvider).getSourceKeyStatus('mangalib');
      state = state.copyWith(
        connected: status.hasKey,
        maskedKey: status.maskedKey,
        userId: await readStoredMangalibUserId(),
      );
    } catch (_) {
      // Status is cosmetic; the import itself degrades to manual token entry.
    } finally {
      state = state.copyWith(checking: false);
    }
  }

  /// Manual token fallback (when browser pickup is unavailable): persists the
  /// token the user pasted by hand. Returns true when the token was saved and
  /// the shared state now reports connected.
  Future<bool> saveMangalibToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    final dict = I18nDictionary(ref.read(i18nProvider));
    try {
      await ref.read(apiClientProvider).saveSourceKey('mangalib', trimmed);
      await readMangalibStatus();
      showToast(
        title: dict.tr('importModal.mangalibAuth.connectedToast'),
        description: dict.tr('toast.descAuth'),
      );
      return true;
    } catch (error) {
      showToast(
        title: dict.tr('importModal.mangalibAuth.saveFailed'),
        description: dict.tr('toast.descRetry'),
        type: 'error',
      );
      return false;
    }
  }

  /// Applies a session picked up from the user's browser (server already
  /// stored the token encrypted): remembers the non-secret User ID for
  /// one-click imports and refreshes the shared state so the card flips to
  /// connected.
  Future<void> adoptBrowserSession(int? userId) async {
    if (userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(userIdKey, '$userId');
      } catch (_) {
        // Storage unavailable: the user can still type the ID manually.
      }
    }
    // Read the server status directly: the detector already persisted the
    // token.
    await readMangalibStatus();
    final dict = I18nDictionary(ref.read(i18nProvider));
    showToast(
      title: dict.tr('importModal.mangalibAuth.connectedToast'),
      description: dict.tr('toast.descAuth'),
    );
  }

  /// Clears the stored token and the remembered User ID.
  Future<void> disconnectMangalib() async {
    final dict = I18nDictionary(ref.read(i18nProvider));
    try {
      await ref.read(apiClientProvider).saveSourceKey('mangalib', '');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(userIdKey);
      } catch (_) {
        // Ignore: nothing to clean up locally.
      }
      await refreshMangalibAuth();
      showToast(
        title: dict.tr('importModal.mangalibAuth.disconnectedToast'),
        description: dict.tr('toast.descAuthOff'),
      );
    } catch (_) {
      showToast(
        title: dict.tr('importModal.mangalibAuth.saveFailed'),
        description: dict.tr('toast.descRetry'),
        type: 'error',
      );
    }
  }
}

final mangalibAuthProvider =
    NotifierProvider<MangalibAuthController, MangalibAuthState>(
        MangalibAuthController.new);
