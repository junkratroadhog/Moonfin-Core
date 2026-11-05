import 'package:dio/dio.dart';

/// Native: Dio streams a POST response body incrementally, so the NDJSON lines arrive as the server
/// flushes each indexer.
Future<Stream<List<int>>?> openPickerStream(
  Dio dio,
  String url, {
  required Map<String, String> headers,
  required Object jsonBody,
  required CancelToken cancelToken,
}) async {
  final response = await dio.post<ResponseBody>(
    url,
    data: jsonBody,
    options: Options(
      headers: headers,
      responseType: ResponseType.stream,
      // The caller ends the stream itself; Dio's receive timeout stays out of it.
      receiveTimeout: Duration.zero,
    ),
    cancelToken: cancelToken,
  );
  return response.data?.stream.cast<List<int>>();
}
