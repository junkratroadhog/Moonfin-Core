import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'picker_models.dart';

class PickerService {
  final String baseUrl;
  final Dio _dio;

  PickerService({
    String? baseUrl,
    Dio? dio,
  })  : baseUrl = baseUrl ?? 'http://192.168.0.243:9898',
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ));

  /// Fetches available releases from Radarr & indexers (including 1TamilMV)
  Future<PickerReleasesResponse> fetchReleases({
    required int tmdbId,
    String? title,
    int? year,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/picker/api/releases',
        data: {
          'tmdbId': tmdbId,
          'title': ?title,
          'year': ?year,
        },
      );

      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return PickerReleasesResponse.fromJson(res.data as Map<String, dynamic>);
      } else {
        debugPrint('[PickerService] Failed to fetch releases: ${res.statusCode}');
        return PickerReleasesResponse(
          movieId: 0,
          title: title ?? '',
          year: year ?? 0,
          releases: const [],
        );
      }
    } catch (e, st) {
      debugPrint('[PickerService] Error fetching releases: $e\n$st');
      return PickerReleasesResponse(
        movieId: 0,
        title: title ?? '',
        year: year ?? 0,
        releases: const [],
      );
    }
  }

  /// Tells the backend to grab a specific release
  Future<bool> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/picker/api/grab',
        data: {
          'guid': guid,
          'indexerId': indexerId,
        },
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[PickerService] Error grabbing release: $e');
      return false;
    }
  }

  /// Gets the current download progress and status for an ongoing grab
  Future<GrabStatus?> getGrabStatus(String title) async {
    try {
      final res = await _dio.get(
        '$baseUrl/picker/api/grab-status',
        queryParameters: {'title': title},
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return GrabStatus.fromJson(res.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[PickerService] Error fetching grab status: $e');
    }
    return null;
  }

  /// Cancels or deletes an active grab
  Future<bool> deleteGrab(String title) async {
    try {
      final res = await _dio.post(
        '$baseUrl/picker/api/delete-grab',
        data: {'title': title},
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[PickerService] Error deleting grab: $e');
      return false;
    }
  }
}

