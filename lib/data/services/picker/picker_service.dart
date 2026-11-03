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

  /// Base URL of the scraper proxy (defaulting to host of media server on port 5056)
  String get baseUrl {
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
}
