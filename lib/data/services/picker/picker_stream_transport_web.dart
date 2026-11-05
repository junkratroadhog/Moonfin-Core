import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

/// Web: Dio's browser adapter only hands the response over once it has finished, so read the POST
/// response body a chunk at a time with fetch + ReadableStream.getReader() — the NDJSON lines then
/// arrive live and the picker's per-indexer progress ticks as each indexer completes.
Future<Stream<List<int>>?> openPickerStream(
  Dio dio,
  String url, {
  required Map<String, String> headers,
  required Object jsonBody,
  required CancelToken cancelToken,
}) async {
  final abort = web.AbortController();
  unawaited(cancelToken.whenCancel.then((_) => abort.abort()));

  final requestHeaders = web.Headers();
  headers.forEach((name, value) => requestHeaders.append(name, value));

  final response = await web.window
      .fetch(
        url.toJS,
        web.RequestInit(
          method: 'POST',
          headers: requestHeaders,
          body: jsonEncode(jsonBody).toJS,
          signal: abort.signal,
        ),
      )
      .toDart;
  if (!response.ok) {
    throw StateError('releases/stream answered ${response.status}');
  }
  final body = response.body;
  if (body == null) return null;

  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  final controller = StreamController<List<int>>();
  controller
    ..onListen = () async {
      try {
        while (true) {
          final chunk = await reader.read().toDart;
          if (chunk.done) break;
          final value = chunk.value;
          if (value != null) controller.add((value as JSUint8Array).toDart);
        }
      } catch (error) {
        if (!controller.isClosed) controller.addError(error);
      }
      if (!controller.isClosed) await controller.close();
    }
    ..onCancel = () => abort.abort();
  return controller.stream;
}
