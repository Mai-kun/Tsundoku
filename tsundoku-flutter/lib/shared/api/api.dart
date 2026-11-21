/// 1:1 port of `mediatracker-ui/src/shared/api/api.ts`.
///
/// Модульные функции fetch → методы [TsundokuApi] (dio, `baseUrl` инъекция).
/// `apiFetch` → [_guard]: колбеки onRequestStart/onRequestEnd (в приложении
/// подключаются к networkActivityProvider — полный аналог networkActivity
/// begin/end; в тестах — счётчик) + 15s timeout (`AbortSignal.timeout`).
/// `Blob` → `Uint8List`; `updateStatus` union → два метода (решение #9);
/// `errorMessage` принимает [Locale] явно.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/index.dart';
import '../types/dtos.dart';
import '../types/enums.dart';
import '../types/models.dart';
import 'network_activity.dart';
const String mediaEndpoint = '/api/media';
const String externalEndpoint = '/api/external';

typedef ValidationErrors = Map<String, List<String>>;

class ApiError implements Exception {
  final int status;
  final String detail;
  final ValidationErrors validationErrors;

  ApiError(
    this.status, {
    this.detail = '',
    this.validationErrors = const <String, List<String>>{},
  });

  @override
  String toString() =>
      'ApiError($status, ${detail.isEmpty ? 'API request failed' : detail})';
}

/// `errorMessage(error)`: validationErrors → detail → errors.requestFailed;
/// не-ApiError → errors.unexpected. Локаль передаётся явно (функция вне
/// виджет-контекста; потребители берут локаль из i18nProvider).
String errorMessage(Object error, Locale locale) {
  if (error is ApiError) {
    final validationMessage = error.validationErrors.values
        .expand((messages) => messages)
        .firstOrNull;
    if (validationMessage != null) return validationMessage;
    if (error.detail.isNotEmpty) return error.detail;
    return I18nDictionary(locale).tr('errors.requestFailed');
  }
  return I18nDictionary(locale).tr('errors.unexpected');
}

class ProblemDetails {
  final String? detail;
  final String? title;
  final ValidationErrors errors;
  const ProblemDetails({this.detail, this.title, this.errors = const {}});
}

ProblemDetails readProblemDetails(Object? value) {
  if (value is! Map<String, dynamic>) return const ProblemDetails();
  final errorsRaw = value['errors'];
  final errors = <String, List<String>>{};
  if (errorsRaw is Map) {
    errorsRaw.forEach((key, messages) {
      if (messages is List && messages.every((m) => m is String)) {
        errors[key as String] = messages.cast<String>().toList();
      }
    });
  }
  return ProblemDetails(
    detail: value['detail'] is String ? value['detail'] as String : null,
    title: value['title'] is String ? value['title'] as String : null,
    errors: errors,
  );
}

/// Что GET /api/media возвращает со счётчиком: строка [MediaItem] +
/// True DB-side total behind the server's limit window (X-Total-Count).
class MediaListPage {
  final List<MediaItem> items;
  final int totalCount;
  const MediaListPage({required this.items, required this.totalCount});
}

class MangalibDetectResult {
  final bool success;
  final int? userId;
  final String? username;
  /// Where the session was found (browser profile), for the confirmation toast.
  final String? source;
  final String? message;

  const MangalibDetectResult({
    required this.success,
    required this.userId,
    required this.username,
    required this.source,
    required this.message,
  });

  factory MangalibDetectResult.fromJson(Map<String, dynamic> json) =>
      MangalibDetectResult(
        success: json['success'] as bool,
        userId: (json['userId'] as num?)?.toInt(),
        username: json['username'] as String?,
        source: json['source'] as String?,
        message: json['message'] as String?,
      );
}

class ReadingSettings {
  final int bookPageMinutes;
  final int mangaChapterMinutes;

  const ReadingSettings({
    required this.bookPageMinutes,
    required this.mangaChapterMinutes,
  });

  factory ReadingSettings.fromJson(Map<String, dynamic> json) =>
      ReadingSettings(
        bookPageMinutes: (json['bookPageMinutes'] as num).toInt(),
        mangaChapterMinutes: (json['mangaChapterMinutes'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bookPageMinutes': bookPageMinutes,
        'mangaChapterMinutes': mangaChapterMinutes,
      };

  @override
  bool operator ==(Object other) =>
      other is ReadingSettings &&
      other.bookPageMinutes == bookPageMinutes &&
      other.mangaChapterMinutes == mangaChapterMinutes;

  @override
  int get hashCode => Object.hash(bookPageMinutes, mangaChapterMinutes);
}

/// `type AppLaunchMode = "app_window" | "browser_tab"`.
enum AppLaunchMode {
  appWindow('app_window'),
  browserTab('browser_tab');

  final String wire;
  const AppLaunchMode(this.wire);

  static AppLaunchMode? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static AppLaunchMode fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'AppLaunchMode', 'unknown wire value'));
}

/// `type AppCloseAction = "minimize_to_tray" | "exit_all"`.
enum AppCloseAction {
  minimizeToTray('minimize_to_tray'),
  exitAll('exit_all');

  final String wire;
  const AppCloseAction(this.wire);

  static AppCloseAction? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static AppCloseAction fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'AppCloseAction', 'unknown wire value'));
}

class AppSettings {
  final AppLaunchMode launchMode;
  final AppCloseAction closeAction;

  const AppSettings({required this.launchMode, required this.closeAction});

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        launchMode: AppLaunchMode.fromWire(json['launchMode'] as String),
        closeAction: AppCloseAction.fromWire(json['closeAction'] as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'launchMode': launchMode.wire,
        'closeAction': closeAction.wire,
      };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.launchMode == launchMode &&
      other.closeAction == closeAction;

  @override
  int get hashCode => Object.hash(launchMode, closeAction);
}

/// Настройки выборочного проксирования (пароль приходит только маскированным).
class ProxySettings {
  final bool enabled;
  final String proxyUrl;
  final String? username;
  final bool hasPassword;
  final String? maskedPassword;
  final List<String> proxiedSources;

  const ProxySettings({
    required this.enabled,
    required this.proxyUrl,
    required this.username,
    required this.hasPassword,
    required this.maskedPassword,
    required this.proxiedSources,
  });

  factory ProxySettings.fromJson(Map<String, dynamic> json) => ProxySettings(
        enabled: json['enabled'] as bool,
        proxyUrl: json['proxyUrl'] as String,
        username: json['username'] as String?,
        hasPassword: json['hasPassword'] as bool,
        maskedPassword: json['maskedPassword'] as String?,
        proxiedSources:
            (json['proxiedSources'] as List<Object?>? ?? const []).cast<String>().toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is ProxySettings &&
      other.enabled == enabled &&
      other.proxyUrl == proxyUrl &&
      other.hasPassword == hasPassword &&
      other.proxiedSources == proxiedSources;

  @override
  int get hashCode =>
      Object.hash(enabled, proxyUrl, hasPassword, proxiedSources);
}

/// Пароль: null — не менять сохранённый, пустая строка — сбросить, строка —
/// новый пароль.
class SaveProxySettingsInput {
  final bool enabled;
  final String proxyUrl;
  final String? username;
  final String? password;
  final List<String> proxiedSources;

  const SaveProxySettingsInput({
    required this.enabled,
    required this.proxyUrl,
    required this.username,
    required this.password,
    required this.proxiedSources,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'proxyUrl': proxyUrl,
        'username': username,
        'password': password,
        'proxiedSources': proxiedSources,
      };

  @override
  bool operator ==(Object other) =>
      other is SaveProxySettingsInput && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class UpdateCheckResult {
  final String currentVersion;
  final String? latestVersion;
  final bool isUpdateAvailable;
  final bool canSelfUpdate;
  final String? releaseTitle;
  final String? releaseNotes;
  final String? publishedAt;
  final String? releaseUrl;
  final String? downloadUrl;
  final int? assetSizeBytes;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.isUpdateAvailable,
    required this.canSelfUpdate,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.publishedAt,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.assetSizeBytes,
  });

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json) =>
      UpdateCheckResult(
        currentVersion: json['currentVersion'] as String,
        latestVersion: json['latestVersion'] as String?,
        isUpdateAvailable: json['isUpdateAvailable'] as bool,
        canSelfUpdate: json['canSelfUpdate'] as bool,
        releaseTitle: json['releaseTitle'] as String?,
        releaseNotes: json['releaseNotes'] as String?,
        publishedAt: json['publishedAt'] as String?,
        releaseUrl: json['releaseUrl'] as String?,
        downloadUrl: json['downloadUrl'] as String?,
        assetSizeBytes: (json['assetSizeBytes'] as num?)?.toInt(),
      );
}

class FranchiseReindexResult {
  final int updatedCount;
  const FranchiseReindexResult({required this.updatedCount});

  factory FranchiseReindexResult.fromJson(Map<String, dynamic> json) =>
      FranchiseReindexResult(
        updatedCount: (json['updatedCount'] as num).toInt(),
      );
}

class OfflineModeResponse {
  final bool offlineMode;
  final bool hasDatabases;
  const OfflineModeResponse({
    required this.offlineMode,
    required this.hasDatabases,
  });

  factory OfflineModeResponse.fromJson(Map<String, dynamic> json) =>
      OfflineModeResponse(
        offlineMode: json['offlineMode'] as bool,
        hasDatabases: json['hasDatabases'] as bool,
      );
}

/// Полный API-клиент (1-в-1 функции api.ts).
///
/// Создаётся с dio-инъекцией (в тестах — stub-интерсепторы/адаптер);
/// `baseUrl` нигде не хардкодится и приходит извне (аргумент UI-бинаря).
class TsundokuApi {
  final Dio dio;

  /// networkActivity.begin/end — аналоги в [_guard]; в приложении
  /// apiClientProvider подключает notifier, в тестах — счётчик.
  void Function()? onRequestStart;
  void Function()? onRequestEnd;

  Future<List<SourceInfo>>? _sourcesCachePromise;

  TsundokuApi(this.dio);

  /// Конструктор приложения: dio с baseUrl + 15s timeouts (аналог
  /// `AbortSignal.timeout(15000)` в apiFetch).
  factory TsundokuApi.create({required String baseUrl}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: requestTimeout,
      receiveTimeout: requestTimeout,
      sendTimeout: requestTimeout,
    ));
    return TsundokuApi(dio);
  }

  /// Абсолютный URL запроса из baseUrl + path (платформенные вызовы/тесты).
  String absoluteUrl(String path) => '${dio.options.baseUrl}$path';

  static const Duration requestTimeout = Duration(milliseconds: 15000);

  // ------------------------------------------------------------------
  // Ядро: apiFetch / requestJson / requestVoid.
  // ------------------------------------------------------------------

  Future<Response<T>> _fetch<T>(RequestOptions opts) {
    onRequestStart?.call();
    return dio
        .fetch<T>(opts)
        .whenComplete(() => onRequestEnd?.call());
  }

  RequestOptions _opts(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    ResponseType? responseType,
    String? contentType,
  }) =>
      RequestOptions(
        path: path,
        method: method,
        data: body,
        queryParameters: query ?? const <String, dynamic>{},
        cancelToken: cancelToken,
        responseType: responseType ?? ResponseType.json,
        contentType: contentType,
        // Не-2xx не бросает DioException: статус обрабатывает _isOk/_throwApiError
        // (1-в-1 с throwApiError(response) из TS).
        validateStatus: (_) => true,
        sendTimeout: requestTimeout,
        receiveTimeout: requestTimeout,
      );

  Future<Never> _throwApiError(Response<dynamic> response) async {
    Object? payload;
    try {
      payload = response.data;
    } catch (_) {
      payload = null;
    }
    final problem = readProblemDetails(payload);
    throw ApiError(
      response.statusCode ?? 0,
      detail: (problem.detail ?? problem.title) ?? '',
      validationErrors: problem.errors,
    );
  }

  bool _isOk(Response<dynamic> response) {
    final code = response.statusCode ?? 0;
    return code >= 200 && code < 300;
  }

  Future<T> requestJson<T>(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, dynamic>? query,
    T Function(Object? json)? parse,
    CancelToken? cancelToken,
    String? contentType,
  }) async {
    final response = await _fetch<dynamic>(_opts(
      path,
      method: method,
      body: body,
      query: query,
      cancelToken: cancelToken,
      contentType: contentType,
    ));
    if (!_isOk(response)) {
      await _throwApiError(response);
    }
    final json = response.data;
    if (parse != null) return parse(json);
    return json as T;
  }

  Future<void> requestVoid(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    String? contentType,
  }) async {
    final response = await _fetch<dynamic>(_opts(
      path,
      method: method,
      body: body,
      query: query,
      cancelToken: cancelToken,
      contentType: contentType,
    ));
    if (!_isOk(response)) {
      await _throwApiError(response);
    }
  }

  Future<Uint8List> _exportBytes(String path) async {
    final response = await _fetch<List<int>>(_opts(
      path,
      responseType: ResponseType.bytes,
    ));
    if (!_isOk(response)) {
      await _throwApiError(response);
    }
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  // ------------------------------------------------------------------
  // Media.
  // ------------------------------------------------------------------

  Future<List<MediaItem>> getMedia(
      [MediaFilters filters = const MediaFilters()]) async {
    final page = await getMediaWithCount(filters);
    return page.items;
  }

  Future<MediaListPage> getMediaWithCount(
      [MediaFilters filters = const MediaFilters()]) async {
    final query = <String, dynamic>{
      'sortBy': SortBy.createdAt.wire,
      'sortOrder': SortOrder.desc.wire,
      ...filters.toQueryParameters(),
    };
    query.removeWhere((_, v) => v == null || v == '');
    final response = await _fetch<List<dynamic>>(_opts(
      mediaEndpoint,
      query: query,
    ));
    if (!_isOk(response)) {
      await _throwApiError(response);
    }
    final items = (response.data ?? const [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    // X-Total-Count: True DB-side total behind the server's limit window.
    final rawHeader = response.headers.value('x-total-count');
    final header = int.tryParse(rawHeader ?? '') ?? 0;
    return MediaListPage(
      items: items,
      totalCount: header > 0 ? header : items.length,
    );
  }

  Future<MediaDetail> getMediaItem(String id) => requestJson<MediaDetail>(
        '$mediaEndpoint/$id',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<CreatorSummaryDto?> getCreatorSummary(String name, CreatorRole role,
      {String? excludeId}) async {
    final query = <String, dynamic>{'name': name, 'role': role.wire};
    if (excludeId != null) query['excludeId'] = excludeId;
    return requestJson<CreatorSummaryDto?>(
      '$mediaEndpoint/creator-summary',
      query: query,
      parse: (json) => json == null
          ? null
          : CreatorSummaryDto.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<AdvancedStats> getAdvancedStats(
      {String scope = 'completed', CancelToken? cancelToken}) {
    return requestJson<AdvancedStats>(
      '$mediaEndpoint/stats/advanced',
      query: {'scope': scope},
      cancelToken: cancelToken,
      parse: (json) => AdvancedStats.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<TasteProfile> getTasteProfile(
      {String scope = 'completed', CancelToken? cancelToken}) {
    return requestJson<TasteProfile>(
      '$mediaEndpoint/stats/taste-profile',
      query: {'scope': scope},
      cancelToken: cancelToken,
      parse: (json) => TasteProfile.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<List<ExternalMedia>> searchExternal(
    String type,
    String query, {
    CancelToken? cancelToken,
    String? source,
    bool? byCreator,
    bool? forceRefresh,
  }) {
    final q = <String, dynamic>{'type': type, 'query': query.trim()};
    if (source != null) q['source'] = source;
    if (byCreator == true) q['byCreator'] = 'true';
    if (forceRefresh == true) q['refresh'] = 'true';
    return requestJson<List<ExternalMedia>>(
      '$externalEndpoint/search',
      query: q,
      cancelToken: cancelToken,
      parse: (json) => (json as List<dynamic>)
          .map((e) => ExternalMedia.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<ExternalMedia?> getExternalDetails(
    String type,
    String id,
    String title, {
    String? source,
    CancelToken? cancelToken,
  }) async {
    final q = <String, dynamic>{'type': type, 'id': id, 'title': title};
    if (source != null) q['source'] = source;
    try {
      return await requestJson<ExternalMedia>(
        '$externalEndpoint/details',
        query: q,
        cancelToken: cancelToken,
        parse: (json) => ExternalMedia.fromJson(json as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  Future<MediaDetail> createMedia(CreateMediaBase payload) =>
      requestJson<MediaDetail>(
        mediaEndpoint,
        method: 'POST',
        body: payload.toJson(),
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<MediaDetail> updateMedia(String id, UpdateMediaPayload payload) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id',
        method: 'PUT',
        body: payload.toJson(),
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  /// "Дополнить": fills only the empty fields, from `source` when the user
  /// picked one in the dialog. Never overwrites a value that is already there.
  Future<MediaDetail> enrichMedia(String id, {String? source}) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/enrich',
        method: 'POST',
        body: {'source': source},
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<void> setProgress(String id, int currentProgress) => requestVoid(
        '$mediaEndpoint/$id/progress',
        method: 'PUT',
        body: {'currentProgress': currentProgress},
      );

  Future<void> setSeasonProgress(String id, int currentEpisode) =>
      requestVoid('/api/seasons/$id/progress',
          method: 'PUT', body: {'currentEpisode': currentEpisode});

  /// PUT /status с чистым payload'ом `{status}` (аналог updateStatus(id, число)).
  Future<void> updateStatus(String id, MediaStatus status) =>
      requestVoid('$mediaEndpoint/$id/status',
          method: 'PUT', body: {'status': status.value});

  /// PUT /status с drop-полями (аналог updateStatus(id, {status, dropReason,
  /// dropNotes})); null-поля сериализуются явно (как в TS-объекте).
  Future<void> updateStatusWithDropInfo(
    String id,
    MediaStatus status, {
    String? dropReason,
    String? dropNotes,
  }) =>
      requestVoid('$mediaEndpoint/$id/status', method: 'PUT', body: {
        'status': status.value,
        'dropReason': dropReason,
        'dropNotes': dropNotes,
      });

  Future<void> deleteMedia(String id) =>
      requestVoid('$mediaEndpoint/$id', method: 'DELETE');

  Future<MediaDetail> addCoverByUrl(String id, String url,
      {String? source, bool setAsActive = false}) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/covers',
        method: 'POST',
        body: {'url': url, 'source': source, 'setAsActive': setAsActive},
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<MediaDetail> addCoverByFile(
    String id,
    Uint8List fileBytes, {
    String fileName = 'cover',
    String? source,
    bool setAsActive = false,
  }) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/covers',
        method: 'POST',
        body: FormData.fromMap(<String, dynamic>{
          'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
          'source': ?source,
          if (setAsActive) 'setAsActive': 'true',
        }),
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<MediaDetail> selectCover(String id, String coverId) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/covers/$coverId/select',
        method: 'PUT',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<MediaDetail> deleteCover(String id, String coverId) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/covers/$coverId',
        method: 'DELETE',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<MediaDetail> fetchVolumeCovers(String id) => requestJson<MediaDetail>(
        '$mediaEndpoint/$id/covers/fetch-volumes',
        method: 'POST',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  /// Attaches a file (book, archive, save) to the title; returns the
  /// refreshed attachment list.
  Future<List<MediaAttachment>> attachMediaFile(String id, Uint8List fileBytes,
      {String fileName = 'file'}) {
    final form = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
    });
    return requestJson<List<MediaAttachment>>(
      '$mediaEndpoint/$id/files',
      method: 'POST',
      body: form,
      parse: (json) => (json as List<dynamic>)
          .map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Removes one attachment from disk and from the index; returns the
  /// refreshed list.
  Future<List<MediaAttachment>> detachMediaFile(String id, String fileId) {
    final encoded = Uri.encodeComponent(fileId);
    return requestJson<List<MediaAttachment>>(
      '$mediaEndpoint/$id/files/$encoded',
      method: 'DELETE',
      parse: (json) => (json as List<dynamic>)
          .map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Путь для скачивания вложения (Content-Disposition задаётся сервером).
  String mediaFileDownloadUrl(String id, String fileId) {
    final encoded = Uri.encodeComponent(fileId);
    return '$mediaEndpoint/$id/files/$encoded/download';
  }

  /// Opens the stored file in the OS program associated with its type.
  Future<void> openMediaFile(String id, String fileId) {
    final encoded = Uri.encodeComponent(fileId);
    return requestVoid('$mediaEndpoint/$id/files/$encoded/open',
        method: 'POST');
  }

  /// Скачивание вложения байтами: Content-Disposition задаётся сервером,
  /// имя файла приходит в [MediaAttachment.fileName] (браузерный anchor
  /// download в Svelte → saveFile-фасад, решение #32).
  Future<Uint8List> downloadMediaFile(String id, String fileId) {
    final encoded = Uri.encodeComponent(fileId);
    return _exportBytes('$mediaEndpoint/$id/files/$encoded/download');
  }

  /// Байты произвольного серверного пути (галерея: entry.originalUrl →
  /// fetch→blob→clipboard/saveFile в Svelte).
  Future<Uint8List> downloadMediaFileBytes(String path) => _exportBytes(path);

  /// Привязанные внешние источники (LinkedSourcesSection использует сырой
  /// apiFetch — здесь типизированные методы).
  Future<List<Map<String, dynamic>>> getLinkedSources(String id) {
    return requestJson<List<Map<String, dynamic>>>(
      '$mediaEndpoint/$id/linked-sources',
      parse: (json) =>
          (json as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  Future<List<Map<String, dynamic>>> addLinkedSource(
      String id, String source, String externalId) {
    return requestJson<List<Map<String, dynamic>>>(
      '$mediaEndpoint/$id/linked-sources',
      method: 'POST',
      body: {'source': source, 'externalId': externalId},
      contentType: 'application/json',
      parse: (json) =>
          (json as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  Future<List<Map<String, dynamic>>> makeLinkedSourcePrimary(
      String id, String source) {
    final encoded = Uri.encodeComponent(source);
    return requestJson<List<Map<String, dynamic>>>(
      '$mediaEndpoint/$id/linked-sources/$encoded/primary',
      method: 'PUT',
      parse: (json) =>
          (json as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  Future<List<Map<String, dynamic>>> removeLinkedSource(
      String id, String source) {
    final encoded = Uri.encodeComponent(source);
    return requestJson<List<Map<String, dynamic>>>(
      '$mediaEndpoint/$id/linked-sources/$encoded',
      method: 'DELETE',
      parse: (json) =>
          (json as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  /// Reveals a server-side path (relative to the data dir) in the platform
  /// file manager.
  /// Клиентский лог ошибок (window.onerror из main.ts → FlutterError.onError).
  Future<void> sendClientLog(String message, [String? stack]) =>
      requestVoid('/api/logs/client',
          method: 'POST',
          body: <String, dynamic>{
            'message': message,
            'stack': stack,
          });

  Future<void> revealInExplorer(String relativePath) => requestVoid(
        '/api/system/reveal-in-explorer',
        method: 'POST',
        body: {'path': relativePath},
      );

  /// Adds a screenshot to the title's gallery; accepts bytes or a pasted
  /// clipboard blob.
  Future<MediaGalleryItem> uploadGalleryImage(String id, Uint8List image,
      {String? title}) {
    final form = FormData.fromMap(<String, dynamic>{
      'image': MultipartFile.fromBytes(image,
          filename: title ?? 'screenshot.png'),
      'title': ?title,
    });
    return requestJson<MediaGalleryItem>(
      '$mediaEndpoint/$id/gallery',
      method: 'POST',
      body: form,
      parse: (json) => MediaGalleryItem.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Removes one gallery screenshot (folder on disk + index entry).
  Future<void> deleteGalleryImage(String id, String imgId) {
    final encoded = Uri.encodeComponent(imgId);
    return requestVoid('$mediaEndpoint/$id/gallery/$encoded',
        method: 'DELETE');
  }

  /// Makes a gallery screenshot the title's active cover; returns the
  /// updated card.
  Future<MediaDetail> setGalleryAsCover(String id, String imgId) {
    final encoded = Uri.encodeComponent(imgId);
    return requestJson<MediaDetail>(
      '$mediaEndpoint/$id/gallery/$encoded/set-as-cover',
      method: 'POST',
      parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<ImportResultDto> importFile(FormData formData) =>
      requestJson<ImportResultDto>(
        '$mediaEndpoint/import/file',
        method: 'POST',
        body: formData,
        parse: (json) => ImportResultDto.fromJson(json as Map<String, dynamic>),
      );

  Future<ImportResultDto> importSteamProfile(SteamImportPayload payload) =>
      requestJson<ImportResultDto>(
        '$mediaEndpoint/import/steam',
        method: 'POST',
        body: payload.toJson(),
        contentType: 'application/json',
        parse: (json) => ImportResultDto.fromJson(json as Map<String, dynamic>),
      );

  Future<ImportResultDto> importAniListProfile(
      AniListProfilePayload payload) =>
      requestJson<ImportResultDto>(
        '$mediaEndpoint/import/anilist-profile',
        method: 'POST',
        body: payload.toJson(),
        contentType: 'application/json',
        parse: (json) => ImportResultDto.fromJson(json as Map<String, dynamic>),
      );

  Future<ImportResultDto> importMangaLibProfile(
      MangaLibProfilePayload payload) =>
      requestJson<ImportResultDto>(
        '$mediaEndpoint/import/mangalib-profile',
        method: 'POST',
        body: payload.toJson(),
        contentType: 'application/json',
        parse: (json) => ImportResultDto.fromJson(json as Map<String, dynamic>),
      );

  // ------------------------------------------------------------------
  // Lists.
  // ------------------------------------------------------------------

  Future<List<CustomListSummary>> getLists() =>
      requestJson<List<CustomListSummary>>('/api/lists',
          parse: (json) => (json as List<dynamic>)
              .map((e) => CustomListSummary.fromJson(e as Map<String, dynamic>))
              .toList());

  Future<CustomListDetail> getListDetail(String id) =>
      requestJson<CustomListDetail>('/api/lists/$id',
          parse: (json) =>
              CustomListDetail.fromJson(json as Map<String, dynamic>));

  Future<String> createList(CreateListPayload payload) async {
    final json = await requestJson<Map<String, dynamic>>('/api/lists',
        method: 'POST',
        body: payload.toJson(),
        contentType: 'application/json');
    return json['id'] as String;
  }

  Future<void> updateList(String id, UpdateListPayload payload) =>
      requestVoid('/api/lists/$id',
          method: 'PUT', body: payload.toJson());

  Future<void> deleteList(String id) =>
      requestVoid('/api/lists/$id', method: 'DELETE');

  Future<void> addMediaToList(String listId, String mediaId) =>
      requestVoid('/api/lists/$listId/items',
          method: 'POST', body: {'mediaId': mediaId});

  Future<void> removeMediaFromList(String listId, String mediaId) =>
      requestVoid('/api/lists/$listId/items/$mediaId', method: 'DELETE');

  Future<List<String>> getListsForMedia(String mediaId) =>
      requestJson<List<String>>('$mediaEndpoint/$mediaId/lists',
          parse: (json) => (json as List<dynamic>).cast<String>().toList());

  /// Re-reads the provider. `fillMissing` turns the overwrite into a gap fill,
  /// which is what the "keep my edits" branch of the refresh dialog sends.
  Future<MediaDetail> refreshMetadata(String id,
      {bool fillMissing = false}) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/refresh',
        method: 'POST',
        body: {'fillMissing': fillMissing},
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  /// Re-points an item at another provider's entity. Unlike refresh, which
  /// re-reads the id the row already stores, this takes a new id from a
  /// source the user picked explicitly.
  Future<MediaDetail> relinkMedia(
    String id, {
    required String externalId,
    required String source,
    required String type,
    String? title,
  }) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/relink',
        method: 'POST',
        body: {
          'externalId': externalId,
          'source': source,
          'type': type,
          'title': ?title,
        },
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<List<SourceInfo>> getSources({bool forceRefresh = false}) {
    final cached = _sourcesCachePromise;
    if (!forceRefresh && cached != null) return cached;
    final promise = requestJson<List<SourceInfo>>(
      '/api/settings/sources',
      parse: (json) => (json as List<dynamic>)
          .map((e) => SourceInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    ).then<List<SourceInfo>>((list) {
      // 1-в-1 TS: кэш хранит resolved-promise до invalidate/ошибки.
      return list;
    }, onError: (Object err) {
      _sourcesCachePromise = null;
      throw err;
    });
    _sourcesCachePromise = promise;
    return promise;
  }
  void invalidateSourcesCache() {
    _sourcesCachePromise = null;
  }

  Future<ToggleResult> toggleSourceEnabled(String sourceId, bool enabled) {
    invalidateSourcesCache();
    return requestJson<ToggleResult>(
      '/api/settings/sources/$sourceId/toggle',
      method: 'PUT',
      body: {'enabled': enabled},
      contentType: 'application/json',
      parse: (json) => ToggleResult.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<ConnectionTestResult> testSourceConnection(String sourceId) =>
      requestJson<ConnectionTestResult>(
        '/api/settings/sources/$sourceId/test',
        method: 'POST',
        parse: (json) =>
            ConnectionTestResult.fromJson(json as Map<String, dynamic>),
      );

  Future<SourceKeyStatus> saveSourceKey(String sourceId, String apiKey) {
    invalidateSourcesCache();
    return _sourceKeyRequest('/api/settings/sources/$sourceId/key',
        method: 'PUT', body: {'apiKey': apiKey});
  }

  Future<SourceKeyStatus> getSourceKeyStatus(String sourceId) =>
      _sourceKeyRequest('/api/settings/sources/$sourceId/key', method: 'GET');

  Future<SourceKeyStatus> _sourceKeyRequest(String path,
      {required String method, Map<String, dynamic>? body}) {
    return requestJson<SourceKeyStatus>(path,
        method: method,
        body: body,
        contentType: body != null ? 'application/json' : null,
        parse: (json) =>
            SourceKeyStatus.fromJson(json as Map<String, dynamic>));
  }

  /// Picks up the SocialLib session from the user's own browsers (Zen /
  /// Firefox / the isolated Tsundoku Chromium profile). Returns null when no
  /// session exists (HTTP 404) — the caller shows the "open login page"
  /// fallback.
  Future<MangalibDetectResult?> detectMangalibBrowserSession() =>
      _detectBrowserSession('/api/settings/sources/mangalib/detect-token');

  /// Opens the MangaLib login page in the system browser.
  Future<void> openMangalibLoginPage() =>
      requestVoid('/api/settings/sources/mangalib/open-login', method: 'POST');

  /// Picks up the Simkl session from the user's own browsers. Returns null
  /// when no session exists (HTTP 404). The token lands in its own slot —
  /// Simkl's client_id key stays untouched, Auth V2 requires both.
  Future<MangalibDetectResult?> detectSimklBrowserSession() =>
      _detectBrowserSession('/api/settings/sources/simkl/detect-token');

  Future<MangalibDetectResult?> _detectBrowserSession(String path) async {
    final response = await _fetch<dynamic>(_opts(path, method: 'POST'));
    if (response.statusCode == 404) return null;
    if (!_isOk(response)) {
      await _throwApiError(response);
    }
    invalidateSourcesCache();
    return MangalibDetectResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Asks the Tsundoku server (tray + web) to shut down gracefully.
  Future<void> shutdownApp() =>
      requestVoid('/api/system/shutdown', method: 'POST');

  Future<List<String>> getCategoryOrder() =>
      requestJson<List<String>>('/api/settings/category-order',
          parse: (json) => (json as List<dynamic>).cast<String>().toList());

  Future<List<String>> saveCategoryOrder(List<String> order) =>
      requestJson<List<String>>('/api/settings/category-order',
          method: 'PUT',
          body: order,
          contentType: 'application/json',
          parse: (json) => (json as List<dynamic>).cast<String>().toList());

  Future<Map<String, List<String>>> getSourcePriority() =>
      requestJson<Map<String, List<String>>>('/api/settings/source-priority',
          parse: _parseStringListMap);

  Future<Map<String, List<String>>> saveSourcePriority(
      Map<String, List<String>> priority) =>
      requestJson<Map<String, List<String>>>('/api/settings/source-priority',
          method: 'PUT',
          body: priority,
          contentType: 'application/json',
          parse: _parseStringListMap);

  static Map<String, List<String>> _parseStringListMap(Object? json) {
    final raw = json as Map<String, dynamic>;
    return raw.map(
        (k, v) => MapEntry(k, (v as List<Object?>).cast<String>().toList()));
  }

  Future<AppSettings> getAppSettings() => requestJson<AppSettings>(
        '/api/settings/app',
        parse: (json) => AppSettings.fromJson(json as Map<String, dynamic>),
      );

  Future<AppSettings> saveAppSettings(AppSettings settings) =>
      requestJson<AppSettings>(
        '/api/settings/app',
        method: 'PUT',
        body: settings.toJson(),
        contentType: 'application/json',
        parse: (json) => AppSettings.fromJson(json as Map<String, dynamic>),
      );

  Future<ProxySettings> getProxySettings() => requestJson<ProxySettings>(
        '/api/settings/proxy',
        parse: (json) => ProxySettings.fromJson(json as Map<String, dynamic>),
      );

  Future<ProxySaveResult> saveProxySettings(SaveProxySettingsInput input) {
    invalidateSourcesCache();
    return requestJson<ProxySaveResult>(
      '/api/settings/proxy',
      method: 'PUT',
      body: input.toJson(),
      contentType: 'application/json',
      parse: (json) => ProxySaveResult.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<ProxyTestResult> testProxy({
    required String proxyUrl,
    required String? username,
    /// null — использовать сохранённый пароль; строка — проверить новый.
    required String? password,
    required bool useStoredPassword,
  }) {
    return requestJson<ProxyTestResult>(
      '/api/settings/proxy/test',
      method: 'POST',
      body: {
        'proxyUrl': proxyUrl,
        'username': username,
        'password': password,
        'useStoredPassword': useStoredPassword,
      },
      contentType: 'application/json',
      parse: (json) => ProxyTestResult.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Один клик на карточке источника: пустить конкретный источник через прокси.
  Future<SourceProxyToggleResult> toggleSourceProxy(
      String sourceId, bool proxied) {
    invalidateSourcesCache();
    return requestJson<SourceProxyToggleResult>(
      '/api/settings/proxy/sources/$sourceId/toggle',
      method: 'POST',
      body: {'proxied': proxied},
      contentType: 'application/json',
      parse: (json) =>
          SourceProxyToggleResult.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<ReadingSettings> getReadingSettings() => requestJson<ReadingSettings>(
        '/api/settings/reading',
        parse: (json) => ReadingSettings.fromJson(json as Map<String, dynamic>),
      );

  Future<ReadingSettings> saveReadingSettings(ReadingSettings settings) =>
      requestJson<ReadingSettings>(
        '/api/settings/reading',
        method: 'PUT',
        body: settings.toJson(),
        contentType: 'application/json',
        parse: (json) => ReadingSettings.fromJson(json as Map<String, dynamic>),
      );

  Future<String> translateText(String text,
      {String targetLanguage = 'ru'}) async {
    final json = await requestJson<Map<String, dynamic>>(
      '/api/external/translate',
      method: 'POST',
      body: {'text': text, 'targetLanguage': targetLanguage},
      contentType: 'application/json',
    );
    return json['translatedText'] as String;
  }

  Future<GameAchievementsResponse> getGameAchievements({
    String? steamAppId,
    String? rawgId,
    String? title,
    String? externalSource,
    String? externalId,
  }) {
    final query = <String, dynamic>{
      'steamAppId': ?steamAppId,
      'rawgId': ?rawgId,
      'title': ?title,
      'externalSource': ?externalSource,
      'externalId': ?externalId,
    };
    return requestJson<GameAchievementsResponse>(
      '/api/external/games/achievements',
      query: query,
      parse: (json) =>
          GameAchievementsResponse.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<List<GameRelatedItem>> getGameRelated({
    String? rawgId,
    String? title,
    String? externalSource,
    String? externalId,
  }) {
    final query = <String, dynamic>{
      'rawgId': ?rawgId,
      'title': ?title,
      'externalSource': ?externalSource,
      'externalId': ?externalId,
    };
    return requestJson<List<GameRelatedItem>>(
      '/api/external/games/related',
      query: query,
      parse: (json) => (json as List<dynamic>)
          .map((e) => GameRelatedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Related / recommended titles for one source. `kind` is "related" or
  /// "recommendations"; the caller must name the source explicitly because
  /// these are only ever fetched on request.
  Future<List<ExternalRelation>> getExternalRelations({
    String? type,
    String? externalId,
    String? title,
    required String source,
    required String kind,
  }) {
    final query = <String, dynamic>{
      'type': ?type,
      'externalId': ?externalId,
      'title': ?title,
      'source': source,
      'kind': kind,
    };
    return requestJson<List<ExternalRelation>>(
      '/api/external/relations',
      query: query,
      parse: (json) => (json as List<dynamic>)
          .map((e) => ExternalRelation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<CalendarScheduleDto> getCalendar(
      {String? from, String? to, CancelToken? cancelToken}) {
    final query = <String, dynamic>{
      'from': ?from,
      'to': ?to,
    };
    return requestJson<CalendarScheduleDto>(
      '$mediaEndpoint/calendar',
      query: query,
      cancelToken: cancelToken,
      parse: (json) =>
          CalendarScheduleDto.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<MediaDetail> triggerAutoRefresh(String mediaId) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$mediaId/auto-refresh/trigger',
        method: 'POST',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  /// RFC 5545 calendar feed (episodes + releases) for external calendars.
  Future<Uint8List> exportCalendarIcs() =>
      _exportBytes('$mediaEndpoint/calendar/ics');

  /// Titles with a release in the next 30 days the user is behind on
  /// (ongoings + franchise sequels).
  Future<List<BacklogDeadlineDto>> getBacklogDeadlines(
      {CancelToken? cancelToken}) {
    return requestJson<List<BacklogDeadlineDto>>(
      '$mediaEndpoint/calendar/backlog-deadlines',
      cancelToken: cancelToken,
      parse: (json) => (json as List<dynamic>)
          .map((e) => BacklogDeadlineDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Library rows the enrichment job parked in `NeedsReview`, each with its
  /// candidate matches.
  Future<List<PendingMatchItemDto>> getPendingMatches() {
    return requestJson<List<PendingMatchItemDto>>(
      '$mediaEndpoint/pending-matches',
      parse: (json) => (json as List<dynamic>)
          .map((e) => PendingMatchItemDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Applies the candidate the user confirmed and returns the enriched row.
  Future<MediaDetail> resolvePendingMatch(
    String id, {
    required String externalId,
    required String source,
    String? type,
    String? title,
  }) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$id/resolve-match',
        method: 'POST',
        body: {
          'externalId': externalId,
          'source': source,
          'type': ?type,
          'title': ?title,
        },
        contentType: 'application/json',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  /// Skips one review row: candidates are wiped, the row goes back to Ready.
  Future<void> dismissPendingMatch(String id) =>
      requestVoid('$mediaEndpoint/$id/dismiss-match', method: 'POST');

  /// Skips every review row at once.
  Future<void> dismissAllPendingMatches() =>
      requestVoid('$mediaEndpoint/dismiss-all-matches', method: 'POST');

  /// Auto-picks the top candidate of every review row that scans strong
  /// enough; weak rows stay in review.
  Future<ResolveAllResult> resolveAllPendingMatchesByPriority() =>
      requestJson<ResolveAllResult>(
        '$mediaEndpoint/resolve-all-by-priority',
        method: 'POST',
        parse: (json) =>
            ResolveAllResult.fromJson(json as Map<String, dynamic>),
      );

  /// Verdict "merge" on a duplicate-conflict review row: the duplicate's
  /// sources, ratings and missing data join the existing title and the
  /// duplicate row is deleted, so the library keeps one card.
  Future<MediaDetail> mergeDuplicateSources(
          String existingId, String duplicateId) =>
      requestJson<MediaDetail>(
        '$mediaEndpoint/$existingId/merge-duplicate/$duplicateId',
        method: 'POST',
        parse: (json) => MediaDetail.fromJson(json as Map<String, dynamic>),
      );

  Future<List<HistoryEvent>> getHistoryEvents(
      {String? mediaId, String? date}) {
    final query = <String, dynamic>{
      'mediaId': ?mediaId,
      'date': ?date,
    };
    return requestJson<List<HistoryEvent>>('/api/history',
        query: query,
        parse: (json) => (json as List<dynamic>)
            .map((e) => HistoryEvent.fromJson(e as Map<String, dynamic>))
            .toList());
  }

  Future<void> clearAllHistory() =>
      requestVoid('/api/history', method: 'DELETE');

  /// Removes one activity-log entry. `id` is the event id, as listed by
  /// getHistoryEvents.
  Future<void> deleteHistoryEvent(String id) =>
      requestVoid('/api/history/$id', method: 'DELETE');

  Future<Uint8List> exportBackup() =>
      _exportBytes('/api/settings/backup/export');

  /// Clean, import-compatible dump of the whole library (fields match the
  /// Custom Import parser).
  Future<Uint8List> exportLibraryJson() =>
      _exportBytes('/api/settings/export/json');

  /// RFC 4180 CSV dump of the whole library, UTF-8 BOM included for Excel.
  Future<Uint8List> exportLibraryCsv() =>
      _exportBytes('/api/settings/export/csv');

  Future<void> restoreBackup(Uint8List backupBytes,
      {String fileName = 'backup'}) async {
    final form = FormData.fromMap(<String, dynamic>{
      'backupFile': MultipartFile.fromBytes(backupBytes, filename: fileName),
    });
    final response =
        await _fetch<dynamic>(_opts('/api/settings/backup/restore',
            method: 'POST', body: form));
    if (!_isOk(response)) {
      await _throwApiError(response);
    }
  }

  Future<void> resetAllData({bool keepApiKeys = true}) => requestVoid(
        '/api/settings/reset',
        method: 'POST',
        body: {'keepApiKeys': keepApiKeys},
      );

  Future<List<ApiTokenSummary>> getApiTokens() =>
      requestJson<List<ApiTokenSummary>>('/api/settings/tokens',
          parse: (json) => (json as List<dynamic>)
              .map((e) => ApiTokenSummary.fromJson(e as Map<String, dynamic>))
              .toList());

  Future<CreateApiTokenResponse> createApiToken(String name,
      {int? expiresInDays}) {
    return requestJson<CreateApiTokenResponse>(
      '/api/settings/tokens',
      method: 'POST',
      body: {'name': name, 'expiresInDays': expiresInDays},
      contentType: 'application/json',
      parse: (json) =>
          CreateApiTokenResponse.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<void> revokeApiToken(String id) =>
      requestVoid('/api/settings/tokens/$id', method: 'DELETE');

  Future<UpdateCheckResult> checkAppUpdate() => requestJson<UpdateCheckResult>(
        '/api/settings/update/check',
        parse: (json) =>
            UpdateCheckResult.fromJson(json as Map<String, dynamic>),
      );

  Future<void> applyAppUpdate() =>
      requestVoid('/api/settings/update/apply', method: 'POST');

  Future<StorageSettings> getStorageSettings() => requestJson<StorageSettings>(
        '/api/settings/storage',
        parse: (json) => StorageSettings.fromJson(json as Map<String, dynamic>),
      );

  Future<bool> saveStorageSettings(StorageRequest payload) async {
    final json = await requestJson<Map<String, dynamic>>(
      '/api/settings/storage',
      method: 'POST',
      body: payload.toJson(),
      contentType: 'application/json',
    );
    return json['restartScheduled'] as bool;
  }

  Future<List<GoalDto>> getGoals(int year) =>
      requestJson<List<GoalDto>>('/api/goals?year=$year',
          parse: (json) => (json as List<dynamic>)
              .map((e) => GoalDto.fromJson(e as Map<String, dynamic>))
              .toList());

  Future<GoalDto> createGoal(CreateGoalPayload payload) =>
      requestJson<GoalDto>('/api/goals',
          method: 'POST',
          body: payload.toJson(),
          contentType: 'application/json',
          parse: (json) => GoalDto.fromJson(json as Map<String, dynamic>));

  Future<void> deleteGoal(String id) =>
      requestVoid('/api/goals/$id', method: 'DELETE');

  Future<List<ApiRateLimitStatus>> getRateLimits() =>
      requestJson<List<ApiRateLimitStatus>>('/api/system/rate-limits',
          parse: (json) => (json as List<dynamic>)
              .map((e) => ApiRateLimitStatus.fromJson(e as Map<String, dynamic>))
              .toList());

  Future<OfflineDatabasesSummaryDto> getOfflineDatabases() =>
      requestJson<OfflineDatabasesSummaryDto>('/api/settings/offline-databases',
          parse: (json) => OfflineDatabasesSummaryDto.fromJson(
              json as Map<String, dynamic>));

  Future<void> reindexOfflineDatabases() => requestVoid(
      '/api/settings/offline-databases/reindex',
      method: 'POST');

  Future<SearchCacheInfoDto> getSearchCacheInfo() =>
      requestJson<SearchCacheInfoDto>('/api/settings/search-cache',
          parse: (json) =>
              SearchCacheInfoDto.fromJson(json as Map<String, dynamic>));

  Future<void> clearSearchCache() =>
      requestVoid('/api/settings/search-cache', method: 'DELETE');

  Future<FranchiseReindexResult> reindexFranchises() =>
      requestJson<FranchiseReindexResult>(
        '/api/settings/franchises/reindex',
        method: 'POST',
        parse: (json) =>
            FranchiseReindexResult.fromJson(json as Map<String, dynamic>),
      );

  Future<OfflineModeResponse> getOfflineMode() =>
      requestJson<OfflineModeResponse>('/api/settings/offline-mode',
          parse: (json) =>
              OfflineModeResponse.fromJson(json as Map<String, dynamic>));

  Future<bool> setOfflineMode(bool offlineMode) async {
    final json = await requestJson<Map<String, dynamic>>(
      '/api/settings/offline-mode',
      method: 'PUT',
      body: {'offlineMode': offlineMode},
      contentType: 'application/json',
    );
    return json['offlineMode'] as bool;
  }
}

/// { success, isEnabled } — ответ toggleSourceEnabled.
class ToggleResult {
  final bool success;
  final bool isEnabled;
  const ToggleResult({required this.success, required this.isEnabled});

  factory ToggleResult.fromJson(Map<String, dynamic> json) => ToggleResult(
        success: json['success'] as bool,
        isEnabled: json['isEnabled'] as bool,
      );
}

/// { success, hasKey, maskedKey } — ответы save/get source key.
class SourceKeyStatus {
  final bool success;
  final bool hasKey;
  final String? maskedKey;
  const SourceKeyStatus({
    required this.success,
    required this.hasKey,
    required this.maskedKey,
  });

  factory SourceKeyStatus.fromJson(Map<String, dynamic> json) =>
      SourceKeyStatus(
        success: json['success'] as bool,
        hasKey: json['hasKey'] as bool,
        maskedKey: json['maskedKey'] as String?,
      );
}

/// Ответ saveProxySettings.
class ProxySaveResult {
  final bool success;
  final bool enabled;
  final bool hasPassword;
  final String? maskedPassword;
  final List<String> proxiedSources;
  const ProxySaveResult({
    required this.success,
    required this.enabled,
    required this.hasPassword,
    required this.maskedPassword,
    required this.proxiedSources,
  });

  factory ProxySaveResult.fromJson(Map<String, dynamic> json) =>
      ProxySaveResult(
        success: json['success'] as bool,
        enabled: json['enabled'] as bool,
        hasPassword: json['hasPassword'] as bool,
        maskedPassword: json['maskedPassword'] as String?,
        proxiedSources:
            (json['proxiedSources'] as List<Object?>? ?? const []).cast<String>().toList(),
      );
}

/// Ответ testProxy.
class ProxyTestResult {
  final bool success;
  final int latencyMs;
  final String message;
  const ProxyTestResult({
    required this.success,
    required this.latencyMs,
    required this.message,
  });

  factory ProxyTestResult.fromJson(Map<String, dynamic> json) =>
      ProxyTestResult(
        success: json['success'] as bool,
        latencyMs: (json['latencyMs'] as num).toInt(),
        message: json['message'] as String,
      );
}

/// Ответ toggleSourceProxy.
class SourceProxyToggleResult {
  final bool success;
  final bool isProxied;
  final List<String> proxiedSources;
  const SourceProxyToggleResult({
    required this.success,
    required this.isProxied,
    required this.proxiedSources,
  });

  factory SourceProxyToggleResult.fromJson(Map<String, dynamic> json) =>
      SourceProxyToggleResult(
        success: json['success'] as bool,
        isProxied: json['isProxied'] as bool,
        proxiedSources:
            (json['proxiedSources'] as List<Object?>? ?? const []).cast<String>().toList(),
      );
}

/// Ответ resolveAllPendingMatchesByPriority.
class ResolveAllResult {
  final int resolvedCount;
  final int skippedCount;
  const ResolveAllResult({
    required this.resolvedCount,
    required this.skippedCount,
  });

  factory ResolveAllResult.fromJson(Map<String, dynamic> json) =>
      ResolveAllResult(
        resolvedCount: (json['resolvedCount'] as num).toInt(),
        skippedCount: (json['skippedCount'] as num).toInt(),
      );
}

/// Провайдер приложения: единственный TsundokuApi; `baseUrl` не хардкодится —
/// подставляется при старте (аргумент UI-бинаря `--url http://…`). Здесь же
/// networkActivity колбеки подключаются к глобальному провайдеру (1-в-1 с
/// networkActivity.begin/end внутри apiFetch).
/// Устанавливается при старте UI: `ref.read(apiBaseUrlProvider.notifier).set(url)`.
class ApiBaseUrlController extends Notifier<String> {
  @override
  String build() => '';

  void set(String url) => state = url;
}

final apiBaseUrlProvider =
    NotifierProvider<ApiBaseUrlController, String>(ApiBaseUrlController.new);

final apiClientProvider = Provider<TsundokuApi>((ref) {
  final api = TsundokuApi.create(baseUrl: ref.watch(apiBaseUrlProvider));
  final activity = ref.read(networkActivityProvider.notifier);
  api
    ..onRequestStart = activity.begin
    ..onRequestEnd = activity.end;
  ref.onDispose(() {
    api
      ..onRequestStart = null
      ..onRequestEnd = null;
  });
  return api;
});
