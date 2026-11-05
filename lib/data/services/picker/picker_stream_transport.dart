// POST NDJSON stream transport. Dio's browser adapter only hands the response over once it finishes,
// so on web we read the body incrementally with fetch + ReadableStream.getReader() (same approach as
// settings_stream_transport); native keeps Dio's real streaming. This is what makes the picker's
// per-indexer progress ("N/total") tick live during a search on web instead of all arriving at the end.
export 'picker_stream_transport_io.dart'
    if (dart.library.js_interop) 'picker_stream_transport_web.dart';
