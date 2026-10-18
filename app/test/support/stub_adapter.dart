import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 실제 HTTP 없이 요청을 기록하고 정해 둔 응답(상태 코드 + JSON 본문)을 돌려주는 Dio 어댑터.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this._status, [this._body = '']);

  final int _status;
  final String _body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      _body,
      _status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// [adapter]를 쓰는 테스트용 Dio(`http://test/api/v1`).
Dio stubDio(StubAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
