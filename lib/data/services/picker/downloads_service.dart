import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

// Admin-only qBittorrent transfer management via the scraper — mirrors the TV app's downloadsApi.js.
// Same base + auth as PickerService (Jellyfin token → scraper resolves admin role; non-admins get 403).

class DownloadItem {
  final String id;
  final String title;
  final int size;
  final double progress; // 0..1
  final String state;
  final int speed; // bytes/s (down)
  final int upspeed; // bytes/s (up)
  final int seeds;
  final int peers;
  final int? eta; // seconds
  final double ratio;
  final String? source;

  const DownloadItem({
    required this.id,
    required this.title,
    required this.size,
    required this.progress,
    required this.state,
    required this.speed,
    required this.upspeed,
    required this.seeds,
    required this.peers,
    required this.eta,
    required this.ratio,
    this.source,
  });

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        id: (j['id'] ?? j['hash'] ?? '').toString(),
        title: j['title'] as String? ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        state: j['state'] as String? ?? '',
        speed: (j['speed'] as num?)?.toInt() ?? 0,
        upspeed: (j['upspeed'] as num?)?.toInt() ?? 0,
        seeds: (j['seeds'] as num?)?.toInt() ?? 0,
        peers: (j['peers'] as num?)?.toInt() ?? 0,
        eta: (j['eta'] as num?)?.toInt(),
        ratio: (j['ratio'] as num?)?.toDouble() ?? 0,
        source: j['source'] as String?,
      );
}

class DownloadTotals {
  final int queueSize;
  final int diskFree;
  const DownloadTotals({this.queueSize = 0, this.diskFree = 0});
  factory DownloadTotals.fromJson(Map<String, dynamic> j) => DownloadTotals(
        queueSize: (j['queue_size'] as num?)?.toInt() ?? 0,
        diskFree: (j['disk_free'] as num?)?.toInt() ?? 0,
      );
}

class DownloadsSnapshot {
  final List<DownloadItem> items;
  final DownloadTotals totals;
  const DownloadsSnapshot({this.items = const [], this.totals = const DownloadTotals()});
}

class DownloadsService {
  final Dio _dio;

  DownloadsService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ));

  String get _baseUrl {
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

  String? get _token {
    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      final client = GetIt.instance<MediaServerClient>();
      final t = client.accessToken;
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  Options get _opts {
    final t = _token;
    return Options(headers: {
      'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'X-Jellyfin-Token': t,
    });
  }

  void _check(Response res) {
    final code = res.statusCode ?? 0;
    if (code == 401) throw Exception('Not signed in');
    if (code == 403) throw Exception('Admin only');
    if (code < 200 || code >= 300) throw Exception('Request failed ($code)');
  }

  Future<DownloadsSnapshot> list() async {
    try {
      final res = await _dio.get('$_baseUrl/downloads', options: _opts);
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final d = res.data as Map<String, dynamic>;
        final rawItems = d['items'] as List<dynamic>? ?? const [];
        return DownloadsSnapshot(
          items: rawItems
              .whereType<Map<String, dynamic>>()
              .map(DownloadItem.fromJson)
              .toList(),
          totals: d['totals'] is Map<String, dynamic>
              ? DownloadTotals.fromJson(d['totals'] as Map<String, dynamic>)
              : const DownloadTotals(),
        );
      }
      _check(res);
    } catch (e) {
      debugPrint('[DownloadsService] list failed: $e');
      rethrow;
    }
    return const DownloadsSnapshot();
  }

  Future<void> _post(String path) async {
    final res = await _dio.post('$_baseUrl$path', options: _opts);
    _check(res);
  }

  Future<void> pause(String id) => _post('/downloads/$id/pause');
  Future<void> resume(String id) => _post('/downloads/$id/resume');
  Future<void> recheck(String id) => _post('/downloads/$id/recheck');
  Future<void> pauseAll() => _post('/downloads/pauseAll');
  Future<void> resumeAll() => _post('/downloads/resumeAll');

  // Always remove the files from disk (withData), so the download is wiped from the server and the
  // Disk-free stat actually moves. The delete route is *arr-aware (unmonitors so it can't re-grab).
  Future<void> remove(String id, {bool withData = true}) async {
    final res = await _dio.delete(
      '$_baseUrl/downloads/$id${withData ? '?withData=1' : ''}',
      options: _opts,
    );
    _check(res);
  }

  // On-completion policy: none | pause | remove (server-persisted).
  Future<String> getPolicy() async {
    final res = await _dio.get('$_baseUrl/downloads/settings', options: _opts);
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return (res.data as Map<String, dynamic>)['completionPolicy'] as String? ?? 'none';
    }
    return 'none';
  }

  Future<String> setPolicy(String policy) async {
    final res = await _dio.put(
      '$_baseUrl/downloads/settings',
      data: {'completionPolicy': policy},
      options: _opts,
    );
    _check(res);
    if (res.data is Map<String, dynamic>) {
      return (res.data as Map<String, dynamic>)['completionPolicy'] as String? ?? policy;
    }
    return policy;
  }

  // qBit alternative ("metered") speed-limit mode.
  Future<bool> getSpeedMode() async {
    final res = await _dio.get('$_baseUrl/downloads/speed-mode', options: _opts);
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      return (res.data as Map<String, dynamic>)['alternative'] == true;
    }
    return false;
  }

  Future<bool> toggleSpeedMode() async {
    final res = await _dio.post('$_baseUrl/downloads/speed-mode/toggle', options: _opts);
    _check(res);
    if (res.data is Map<String, dynamic>) {
      return (res.data as Map<String, dynamic>)['alternative'] == true;
    }
    return false;
  }
}
