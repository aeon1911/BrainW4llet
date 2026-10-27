import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:monero_dart/monero_dart.dart';

import '../network/http_json.dart';

/// Ponte entre o `monero_dart` e o nosso cliente HTTP (dart:io). Fala com
/// um nó público do Monero (RPC restrito: JSON, JSON-RPC e binário).
final class MoneroDaemonService with MoneroServiceProvider {
  MoneroDaemonService(this.daemonUrl, this._http);

  final String daemonUrl;
  final HttpJson _http;

  @override
  Future<BaseServiceResponse> doRequest(
    MoneroRequestDetails params, {
    Duration? timeout,
  }) async {
    final (status, bytes) = await _http.postBytes(
      params.encodeUrl(daemonUrl),
      params.encodeBody(),
      params.headers,
    );
    return params.toResponse(bytes, statusCode: status);
  }
}
