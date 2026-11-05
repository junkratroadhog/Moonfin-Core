import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'picker_models.dart';

class PickerService {
  final Dio _dio;

  PickerService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ));

  /// Base URL of the scraper proxy. On web we go SAME-ORIGIN (`/picker/api` on the page's own origin) so
  /// the coreweb nginx proxies to the scraper — no cross-origin host to guess, no CORS, and cached
  /// posters load like any same-origin image. Native derives `<server-host>:5056` exactly like the TV
  /// app (getMoonfinConnection → `<protocol>//<host>:5056/picker/api`).
  String get baseUrl {
    if (kIsWeb) return '${Uri.base.origin}/picker/api';
    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      final client = GetIt.instance<MediaServerClient>();
      if (client.baseUrl.isNotEmpty) {
        final uri = Uri.tryParse(client.baseUrl);
        if (uri != null && uri.host.isNotEmpty) {
          final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
          return '$scheme://${uri.host}:5056/picker/api';
        }
      }
    }
    return 'http://192.168.0.243:5056/picker/api';
  }

  /// Active Jellyfin user access token for authenticating with scraper
  String? get token {
    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      final client = GetIt.instance<MediaServerClient>();
      if (client.accessToken != null && client.accessToken!.isNotEmpty) {
        return client.accessToken;
      }
    }
    return null;
  }

  Map<String, dynamic> get _authHeaders {
    final t = token;
    return {
      'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'X-Jellyfin-Token': t,
    };
  }

  /// Formats a cached poster proxy URL
  String posterUrl(String? original, {int width = 342}) {
    if (original == null || original.isEmpty) return '';
    return '$baseUrl/poster?w=$width&url=${Uri.encodeComponent(original)}';
  }

  /// Fetches available indexers (e.g. 1TamilMV)
  Future<List<IndexerInfo>> getIndexers() async {
    try {
      final res = await _dio.get(
        '$baseUrl/indexers',
        options: Options(headers: _authHeaders),
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final list = res.data['indexers'] as List<dynamic>? ?? const [];
        return list
            .map((e) => IndexerInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[PickerService] Failed to get indexers: $e');
    }
    return const [];
  }

  /// Fetches the scraped catalog for an indexer (e.g. 1tamilmv)
  Future<CatalogResponse> getCatalog(
    String indexerId, {
    bool all = true,
    int page = 1,
  }) async {
    try {
      final query = all ? '?all=1' : '?page=$page';
      final res = await _dio.get(
        '$baseUrl/indexers/$indexerId/catalog$query',
        options: Options(headers: _authHeaders),
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return CatalogResponse.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[PickerService] Failed to load catalog for $indexerId: $e');
    }
    return const CatalogResponse(results: []);
  }

  /// Triggers a sync on an indexer
  Future<bool> syncIndexer(String indexerId, {String mode = 'soft'}) async {
    try {
      final res = await _dio.post(
        '$baseUrl/indexers/$indexerId/sync?mode=$mode',
        options: Options(headers: _authHeaders),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[PickerService] Failed to trigger sync for $indexerId: $e');
      return false;
    }
  }

  /// Admin: hard re-scrape every indexer (the Regional screen's "Refresh All").
  Future<bool> refreshAllIndexers() async {
    try {
      final res = await _dio.post(
        '$baseUrl/indexers/refresh-all',
        options: Options(headers: _authHeaders),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[PickerService] Failed to refresh all indexers: $e');
      return false;
    }
  }

  /// Fetches available releases from Radarr & indexers (including 1TamilMV)
  Future<PickerReleasesResponse> fetchReleases({
    required int tmdbId,
    String? title,
    int? year,
    String? mediaType,
  }) async {
    // 1) If tmdbId is present (> 0), try the fast cached /releases endpoint
    if (tmdbId > 0) {
      try {
        final res = await _dio.post(
          '$baseUrl/releases',
          data: {
            'tmdbId': tmdbId,
            if (title != null) 'title': title,
            if (year != null) 'year': year,
            if (mediaType != null) 'mediaType': mediaType,
          },
          options: Options(headers: _authHeaders),
        );

        if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
          final parsed = PickerReleasesResponse.fromJson(res.data as Map<String, dynamic>);
          if (parsed.releases.isNotEmpty) {
            return parsed;
          }
        }
      } catch (e) {
        debugPrint('[PickerService] Fast releases lookup failed: $e');
      }
    }

    // 2) Fallback to live stream endpoint (supports title-only search for Regional titles)
    if (title != null && title.isNotEmpty) {
      final streamed = await searchReleasesStream(
        tmdbId: tmdbId > 0 ? tmdbId : null,
        title: title,
        year: year,
        mediaType: mediaType,
      );
      return PickerReleasesResponse(
        movieId: tmdbId,
        title: title,
        year: year ?? 0,
        releases: streamed,
      );
    }

    return PickerReleasesResponse(
      movieId: tmdbId,
      title: title ?? '',
      year: year ?? 0,
      releases: const [],
    );
  }

  /// Streaming search (supports title-only or tmdbId search)
  Future<List<TorrentRelease>> searchReleasesStream({
    int? tmdbId,
    required String title,
    int? year,
    String? mediaType,
  }) async {
    final list = <TorrentRelease>[];
    try {
      final res = await _dio.post<ResponseBody>(
        '$baseUrl/releases/stream',
        data: {
          if (tmdbId != null && tmdbId > 0) 'tmdbId': tmdbId,
          'title': title,
          if (year != null && year > 0) 'year': year,
          'mediaType': mediaType ?? 'movie',
        },
        options: Options(
          headers: _authHeaders,
          responseType: ResponseType.stream,
        ),
      );

      final stream = res.data?.stream;
      if (stream != null) {
        final lines = utf8.decoder.bind(stream).transform(const LineSplitter());
        await for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final json = jsonDecode(trimmed) as Map<String, dynamic>;
            if (json['type'] == 'indexer') {
              final raw = json['releases'] as List<dynamic>? ?? const [];
              for (final r in raw) {
                if (r is Map<String, dynamic>) {
                  list.add(TorrentRelease.fromJson(r));
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[PickerService] Error streaming releases: $e');
    }
    return list;
  }

  /// Tells the backend to grab a specific release
  Future<bool> grabRelease({
    required TorrentRelease release,
    int? tmdbId,
    String? title,
    int? year,
    String? mediaType,
  }) async {
    try {
      final data = <String, dynamic>{
        'guid': release.guid,
        'indexerId': release.indexerId,
        'indexer': release.indexer,
        'protocol': release.protocol ?? 'torrent',
        'mediaType': mediaType ?? 'movie',
        if (release.downloadUrl != null && release.downloadUrl!.isNotEmpty)
          'downloadUrl': release.downloadUrl,
        if (release.magnet != null && release.magnet!.isNotEmpty)
          'downloadUrl': release.magnet,
        if (tmdbId != null && tmdbId > 0) 'tmdbId': tmdbId,
        'title': title ?? release.title,
        if (year != null && year > 0) 'year': year,
      };

      final res = await _dio.post(
        '$baseUrl/grab',
        data: data,
        options: Options(headers: _authHeaders),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[PickerService] Error grabbing release: $e');
      return false;
    }
  }

  /// Gets download status by hash or keys
  Future<Map<String, dynamic>> getGrabStatusKeys(List<String> keys) async {
    try {
      final res = await _dio.post(
        '$baseUrl/grab/status',
        data: {'keys': keys},
        options: Options(headers: _authHeaders),
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[PickerService] Error getting grab status: $e');
    }
    return const {};
  }

  /// Cancels or deletes an active grab
  Future<bool> cancelGrab({String? hash, String? key}) async {
    try {
      final res = await _dio.post(
        '$baseUrl/grab/cancel',
        data: {
          if (hash != null) 'hash': hash,
          if (key != null) 'key': key,
        },
        options: Options(headers: _authHeaders),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[PickerService] Error cancelling grab: $e');
      return false;
    }
  }

  /// Deletes a grab and imported files
  Future<bool> deleteGrab({String? hash, String? key}) async {
    try {
      final res = await _dio.post(
        '$baseUrl/grab/delete',
        data: {
          if (hash != null) 'hash': hash,
          if (key != null) 'key': key,
        },
        options: Options(headers: _authHeaders),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[PickerService] Error deleting grab: $e');
      return false;
    }
  }

  /// Cache-first releases lookup — returns cached-or-empty instantly (never the slow live path), so the
  /// picker opens immediately on repeat opens. Mirrors the TV app's `getReleases(tmdbId,{cacheOnly:1})`.
  Future<PickerReleasesResponse> getReleasesCacheOnly({
    required int tmdbId,
    String? mediaType,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/releases',
        data: {
          'tmdbId': tmdbId,
          'cacheOnly': 1,
          if (mediaType != null) 'mediaType': mediaType,
        },
        options: Options(headers: _authHeaders),
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return PickerReleasesResponse.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[PickerService] cacheOnly releases failed: $e');
    }
    return PickerReleasesResponse(
        movieId: tmdbId, title: '', year: 0, releases: const []);
  }

  /// Progressive per-indexer NDJSON stream. Unlike [searchReleasesStream] (which awaits the whole
  /// stream and returns one flat list), this fires [onStart]/[onIndexer]/[onError] as the backend
  /// flushes each indexer — so the picker can show a live "done/total indexers" count and append rows
  /// as they arrive, exactly like the TV app's `streamReleases(tmdbId, onEvent)`. Pass a [cancelToken]
  /// to abort the in-flight fetch when the popup closes or a Refresh supersedes it.
  Future<void> streamReleasesEvents({
    int? tmdbId,
    required String title,
    int? year,
    String? mediaType,
    void Function(int total)? onStart,
    void Function(int done, int total, List<TorrentRelease> releases)? onIndexer,
    void Function(String error)? onError,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.post<ResponseBody>(
      '$baseUrl/releases/stream',
      data: {
        if (tmdbId != null && tmdbId > 0) 'tmdbId': tmdbId,
        'title': title,
        if (year != null && year > 0) 'year': year,
        'mediaType': mediaType ?? 'movie',
      },
      options: Options(
        headers: _authHeaders,
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );

    final stream = res.data?.stream;
    if (stream == null) return;
    final lines = utf8.decoder.bind(stream).transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (json['type']) {
        case 'start':
          onStart?.call((json['total'] as num?)?.toInt() ?? 0);
          break;
        case 'indexer':
          final raw = json['releases'] as List<dynamic>? ?? const [];
          final rels = <TorrentRelease>[];
          for (final r in raw) {
            if (r is Map<String, dynamic>) rels.add(TorrentRelease.fromJson(r));
          }
          onIndexer?.call(
            (json['done'] as num?)?.toInt() ?? 0,
            (json['total'] as num?)?.toInt() ?? 0,
            rels,
          );
          break;
        case 'error':
          onError?.call(json['error'] as String? ?? 'Search failed');
          break;
      }
    }
  }

  /// Grabs a release and returns the created torrent hash (or null) so the picker row can go straight
  /// to its Cancel+progress state before the first status poll lands. Throws on a non-2xx so the caller
  /// can show the row's failed/Retry state. Mirrors the TV app's `grab(rel) → {hash}`.
  Future<String?> grabReleaseResult({
    required TorrentRelease release,
    int? tmdbId,
    String? title,
    int? year,
    String? mediaType,
  }) async {
    final data = <String, dynamic>{
      'guid': release.guid,
      'indexerId': release.indexerId,
      'indexer': release.indexer,
      'protocol': release.protocol ?? 'torrent',
      'mediaType': mediaType ?? 'movie',
      if (release.downloadUrl != null && release.downloadUrl!.isNotEmpty)
        'downloadUrl': release.downloadUrl,
      if (release.magnet != null && release.magnet!.isNotEmpty)
        'downloadUrl': release.magnet,
      if (tmdbId != null && tmdbId > 0) 'tmdbId': tmdbId,
      'title': title ?? release.title,
      if (year != null && year > 0) 'year': year,
    };
    final res = await _dio.post(
      '$baseUrl/grab',
      data: data,
      options: Options(headers: _authHeaders),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final d = res.data;
      if (d is Map<String, dynamic>) return d['hash'] as String?;
      return null;
    }
    throw Exception('Grab failed (${res.statusCode})');
  }
}
