class TorrentRelease {
  final String guid;
  final int indexerId;
  final String indexer;
  final String title;
  final int size;
  final int seeders;
  final int leechers;
  final String quality;
  final String? downloadUrl;
  final String? magnet;
  final String? protocol;
  final List<String> languages;
  final String? resolution;
  final String? source;
  final String? videoCodec;
  final String? audioCodec;
  final String? hdr;
  final String? group;
  final bool rejected;
  final List<String> rejections;

  const TorrentRelease({
    required this.guid,
    required this.indexerId,
    required this.indexer,
    required this.title,
    required this.size,
    required this.seeders,
    required this.leechers,
    required this.quality,
    this.downloadUrl,
    this.magnet,
    this.protocol,
    this.languages = const [],
    this.resolution,
    this.source,
    this.videoCodec,
    this.audioCodec,
    this.hdr,
    this.group,
    this.rejected = false,
    this.rejections = const [],
  });

  factory TorrentRelease.fromJson(Map<String, dynamic> json) {
    final rawLangs = json['languages'] as List<dynamic>? ?? const [];
    return TorrentRelease(
      guid: json['guid'] as String? ?? '',
      indexerId: (json['indexerId'] as num?)?.toInt() ?? 0,
      indexer: json['indexer'] as String? ?? 'Unknown',
      title: json['title'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
      leechers: (json['leechers'] as num?)?.toInt() ?? 0,
      quality: json['quality'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String?,
      magnet: json['magnet'] as String?,
      protocol: json['protocol'] as String? ?? 'torrent',
      languages: rawLangs.map((e) => e.toString()).toList(),
      resolution: json['resolution'] as String?,
      source: json['source'] as String?,
      videoCodec: json['videoCodec'] as String?,
      audioCodec: json['audioCodec'] as String?,
      hdr: json['hdr'] as String?,
      group: json['group'] as String?,
      rejected: json['rejected'] as bool? ?? false,
      rejections: (json['rejections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  String get formattedSize {
    if (size <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = size.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  bool get is4K {
    final t = '$title $quality $resolution'.toLowerCase();
    return t.contains('2160p') || t.contains('4k') || t.contains('uhd');
  }

  bool get is1080p {
    final t = '$title $quality $resolution'.toLowerCase();
    return t.contains('1080p') || t.contains('fhd');
  }

  bool get is720p {
    final t = '$title $quality $resolution'.toLowerCase();
    return t.contains('720p') || t.contains('hd');
  }

  bool get isTamilMV {
    final t = '$title $indexer'.toLowerCase();
    return t.contains('tamilmv') || indexer.toLowerCase().contains('tamilmv');
  }
}

class CatalogItem {
  final String id;
  final String title;
  final int? year;
  final String? posterPath;
  final String mediaType;
  final List<String> languages;
  final String? primaryLanguage;
  final String? quality;
  final String? section; // 'week' or 'recent'
  final String? magnetStatus;
  final int magnetCount;
  final String? overview;
  final double? rating;
  final List<TorrentRelease> releases;

  const CatalogItem({
    required this.id,
    required this.title,
    this.year,
    this.posterPath,
    this.mediaType = 'movie',
    this.languages = const [],
    this.primaryLanguage,
    this.quality,
    this.section,
    this.magnetStatus,
    this.magnetCount = 0,
    this.overview,
    this.rating,
    this.releases = const [],
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    final rawReleases = json['releases'] as List<dynamic>? ?? const [];
    final rawLangs = json['languages'] as List<dynamic>? ?? const [];
    return CatalogItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      year: (json['year'] as num?)?.toInt(),
      posterPath: json['posterPath'] as String?,
      mediaType: json['mediaType'] as String? ?? 'movie',
      languages: rawLangs.map((e) => e.toString()).toList(),
      primaryLanguage: json['primaryLanguage'] as String?,
      quality: json['quality'] as String?,
      section: json['section'] as String?,
      magnetStatus: json['magnetStatus'] as String?,
      magnetCount: (json['magnetCount'] as num?)?.toInt() ?? 0,
      overview: json['overview'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      releases: rawReleases
          .map((e) => TorrentRelease.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CatalogResponse {
  final List<CatalogItem> results;
  final String? syncedAt;
  final bool syncRunning;
  final int? page;
  final int? totalPages;
  final int? totalResults;

  const CatalogResponse({
    required this.results,
    this.syncedAt,
    this.syncRunning = false,
    this.page,
    this.totalPages,
    this.totalResults,
  });

  factory CatalogResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] as List<dynamic>? ?? const [];
    return CatalogResponse(
      results: rawResults
          .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      syncedAt: json['syncedAt'] as String?,
      syncRunning: json['syncRunning'] as bool? ?? false,
      page: (json['page'] as num?)?.toInt(),
      totalPages: (json['totalPages'] as num?)?.toInt(),
      totalResults: (json['totalResults'] as num?)?.toInt(),
    );
  }
}

class IndexerInfo {
  final String id;
  final String name;
  final bool running;
  final String? lastSync;

  const IndexerInfo({
    required this.id,
    required this.name,
    this.running = false,
    this.lastSync,
  });

  factory IndexerInfo.fromJson(Map<String, dynamic> json) {
    return IndexerInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      running: json['running'] as bool? ?? false,
      lastSync: json['lastSync'] as String?,
    );
  }
}

class PickerReleasesResponse {
  final int movieId;
  final String title;
  final int year;
  final String? backdrop;
  final List<TorrentRelease> releases;

  const PickerReleasesResponse({
    required this.movieId,
    required this.title,
    required this.year,
    this.backdrop,
    this.releases = const [],
  });

  factory PickerReleasesResponse.fromJson(Map<String, dynamic> json) {
    final rawReleases = json['releases'] as List<dynamic>? ?? const [];
    return PickerReleasesResponse(
      movieId: (json['movieId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      backdrop: json['backdrop'] as String?,
      releases: rawReleases
          .map((e) => TorrentRelease.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class GrabStatus {
  final String status;
  final double progress;
  final int sizeLeft;
  final String timeleft;
  final String speed;
  final String title;
  final String? hash;

  const GrabStatus({
    required this.status,
    required this.progress,
    required this.sizeLeft,
    required this.timeleft,
    required this.speed,
    required this.title,
    this.hash,
  });

  factory GrabStatus.fromJson(Map<String, dynamic> json) {
    return GrabStatus(
      status: json['status'] as String? ?? 'unknown',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      sizeLeft: (json['sizeLeft'] as num?)?.toInt() ?? 0,
      timeleft: json['timeleft'] as String? ?? '',
      speed: json['speed'] as String? ?? '',
      title: json['title'] as String? ?? '',
      hash: json['hash'] as String?,
    );
  }

  bool get isDownloading =>
      status.toLowerCase() == 'downloading' ||
      status.toLowerCase() == 'queued';

  bool get isCompleted =>
      status.toLowerCase() == 'completed' ||
      status.toLowerCase() == 'imported';
}
