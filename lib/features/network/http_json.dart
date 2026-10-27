import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Falha de rede ou resposta inesperada de um servidor.
final class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cliente HTTP mínimo (dart:io), sem dependências extras. Só é usado pela
/// carteira online; o assinador frio nunca o instancia.
final class HttpJson {
  HttpJson({this.timeout = const Duration(seconds: 25)});

  final Duration timeout;
  final HttpClient _client = HttpClient()..userAgent = 'BrainW4llet';
  int _rpcId = 0;

  void close() => _client.close(force: true);

  Future<String> getText(Uri uri) => _send('GET', uri);

  Future<Object?> getJson(Uri uri) async => jsonDecode(await getText(uri));

  Future<String> postText(
    Uri uri,
    String body, {
    String contentType = 'text/plain',
  }) => _send('POST', uri, body: body, contentType: contentType);

  Future<Object?> postJson(Uri uri, Object body) async => jsonDecode(
    await postText(uri, jsonEncode(body), contentType: 'application/json'),
  );

  /// POST binário cru; devolve (status, corpo). Não lança em status de erro:
  /// quem chama interpreta (usado pelo provedor Monero).
  Future<(int, List<int>)> postBytes(
    Uri uri,
    List<int>? body,
    Map<String, String> headers,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final request = await _client.openUrl('POST', uri).timeout(timeout);
        headers.forEach(request.headers.set);
        // O servidor do monerod (epee) não aceita corpo "chunked".
        request.contentLength = body?.length ?? 0;
        if (body != null) request.add(body);
        final response = await request.close().timeout(timeout);
        final bytes = await response
            .fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d))
            .timeout(timeout * 4);
        if (response.statusCode == 429 && attempt < maxRetries) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        return (response.statusCode, bytes.takeBytes());
      } on Exception catch (e) {
        throw NetworkException('Falha ao acessar ${uri.host}: $e');
      }
    }
  }

  /// Chamada JSON-RPC 2.0; devolve `result` ou lança [NetworkException].
  Future<Object?> rpc(
    Uri uri,
    String method, [
    List<Object?> params = const [],
  ]) async {
    final response = await postJson(uri, {
      'jsonrpc': '2.0',
      'id': ++_rpcId,
      'method': method,
      'params': params,
    });
    if (response is! Map) {
      throw NetworkException('Resposta inválida de $method.');
    }
    final error = response['error'];
    if (error != null) {
      final message = error is Map ? error['message'] : error;
      throw NetworkException('$method: $message');
    }
    return response['result'];
  }

  Future<String> _send(
    String method,
    Uri uri, {
    String? body,
    String? contentType,
  }) async {
    // Servidores públicos limitam a taxa (HTTP 429): espera e tenta de novo.
    for (var attempt = 0; ; attempt++) {
      try {
        return await _sendOnce(
          method,
          uri,
          body: body,
          contentType: contentType,
        );
      } on _RateLimited catch (e) {
        if (attempt >= maxRetries) {
          throw NetworkException(
            '${uri.host} está limitando as consultas. Tente de novo em instantes.',
          );
        }
        final backoff = Duration(seconds: 1 << attempt);
        await Future<void>.delayed(
          e.retryAfter != null && e.retryAfter! > backoff
              ? e.retryAfter!
              : backoff,
        );
      }
    }
  }

  static const int maxRetries = 5;

  Future<String> _sendOnce(
    String method,
    Uri uri, {
    String? body,
    String? contentType,
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        request.headers.contentType = ContentType.parse(contentType!);
        final bytes = utf8.encode(body);
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode == 429) {
        final retryAfter = int.tryParse(
          response.headers.value('retry-after') ?? '',
        );
        throw _RateLimited(
          retryAfter == null ? null : Duration(seconds: retryAfter),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = text.length > 200 ? '${text.substring(0, 200)}…' : text;
        throw NetworkException(
          '${uri.host} respondeu ${response.statusCode}: $detail',
        );
      }
      return text;
    } on NetworkException {
      rethrow;
    } on _RateLimited {
      rethrow;
    } on Exception catch (e) {
      throw NetworkException('Falha ao acessar ${uri.host}: $e');
    }
  }
}

final class _RateLimited implements Exception {
  const _RateLimited(this.retryAfter);

  final Duration? retryAfter;
}
