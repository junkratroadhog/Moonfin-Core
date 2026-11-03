class TorrentRelease {
  final String guid;
  final int indexerId;
  final String indexer;
  final String title;
  final int size;
  final int seeders;
  final int leechers;
  final String quality;
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
    this.rejected = false,
    this.rejections = const [],
  });

  factory TorrentRelease.fromJson(Map<String, dynamic> json) {
    return TorrentRelease(
      guid: json['guid'] as String? ?? '',
      indexerId: (json['indexerId'] as num?)?.toInt() ?? 0,
      indexer: json['indexer'] as String? ?? 'Unknown',
      title: json['title'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
      leechers: (json['leechers'] as num?)?.toInt() ?? 0,
      quality: json['quality'] as String? ?? '',
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
    final t = '$title $quality'.toLowerCase();
    return t.contains('2160p') || t.contains('4k') || t.contains('uhd');
  }

  bool get is1080p {
    final t = '$title $quality'.toLowerCase();
    return t.contains('1080p') || t.contains('fhd');
  }

  bool get is720p {
    final t = '$title $quality'.toLowerCase();
    return t.contains('720p') || t.contains('hd');
  }

  bool get isTamilMV {
    final t = '$title $indexer'.toLowerCase();
    return t.contains('tamilmv') || indexer.toLowerCase().contains('tamilmv');
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

  const GrabStatus({
    required this.status,
    required this.progress,
    required this.sizeLeft,
    required this.timeleft,
    required this.speed,
    required this.title,
  });

  factory GrabStatus.fromJson(Map<String, dynamic> json) {
    return GrabStatus(
      status: json['status'] as String? ?? 'unknown',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      sizeLeft: (json['sizeLeft'] as num?)?.toInt() ?? 0,
      timeleft: json['timeleft'] as String? ?? '',
      speed: json['speed'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }

  bool get isDownloading =>
      status.toLowerCase() == 'downloading' ||
      status.toLowerCase() == 'queued';

  bool get isCompleted =>
      status.toLowerCase() == 'completed' ||
      status.toLowerCase() == 'imported';
}

