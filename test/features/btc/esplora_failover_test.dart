import 'dart:io';

import 'package:brainw4llet/features/btc/esplora_client.dart';
import 'package:brainw4llet/features/network/http_json.dart';
import 'package:flutter_test/flutter_test.dart';

const _stats =
    '{"chain_stats":{"tx_count":2,"funded_txo_sum":5000,"spent_txo_sum":1000},'
    '"mempool_stats":{"tx_count":0,"funded_txo_sum":0,"spent_txo_sum":0}}';

/// Servidor local que responde sempre [status] com [body] e conta os pedidos.
class _Server {
  _Server._(this._server, this.status, this.body) {
    _server.listen((request) {
      hits++;
      request.response
        ..statusCode = status
        ..write(body)
        ..close();
    });
  }

  static Future<_Server> start(int status, String body) async => _Server._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    status,
    body,
  );

  final HttpServer _server;
  final int status;
  final String body;
  int hits = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);
}

void main() {
  late HttpJson http;

  setUp(() => http = HttpJson());
  tearDown(() => http.close());

  FailoverEsplora failover(List<Uri> urls) =>
      FailoverEsplora([for (final url in urls) EsploraClient(url, http)]);

  test('passa ao próximo servidor num erro 5xx e continua nele', () async {
    final down = await _Server.start(503, 'indisponível');
    final up = await _Server.start(200, _stats);
    addTearDown(down.close);
    addTearDown(up.close);
    final backend = failover([down.url, up.url]);

    final first = await backend.addressStats('qualquer');
    expect(first.confirmedBalance, BigInt.from(4000));
    expect(down.hits, 1);
    expect(up.hits, 1);

    await backend.addressStats('qualquer');
    expect(down.hits, 1, reason: 'não deve voltar ao servidor que falhou');
    expect(up.hits, 2);
  });

  test('servidor inalcançável (conexão recusada) também passa ao próximo', () async {
    final gone = await _Server.start(200, _stats);
    final dead = gone.url;
    await gone.close();
    final up = await _Server.start(200, _stats);
    addTearDown(up.close);
    final backend = failover([dead, up.url]);

    final stats = await backend.addressStats('qualquer');

    expect(stats.confirmedBalance, BigInt.from(4000));
    expect(up.hits, 1);
  });

  test('erro de resposta do próprio servidor (4xx) não troca de servidor', () async {
    final rejecting = await _Server.start(400, 'transação recusada');
    final other = await _Server.start(200, _stats);
    addTearDown(rejecting.close);
    addTearDown(other.close);
    final backend = failover([rejecting.url, other.url]);

    await expectLater(
      backend.broadcast('00'),
      throwsA(
        isA<NetworkException>().having((e) => e.retryable, 'retryable', false),
      ),
    );
    expect(other.hits, 0);
  });

  test('se todos falharem, devolve o último erro', () async {
    final a = await _Server.start(502, 'a');
    final b = await _Server.start(503, 'b');
    addTearDown(a.close);
    addTearDown(b.close);
    final backend = failover([a.url, b.url]);

    await expectLater(
      backend.addressStats('qualquer'),
      throwsA(
        isA<NetworkException>().having((e) => e.message, 'message', contains('503')),
      ),
    );
    expect(a.hits, 1);
    expect(b.hits, 1);
  });
}
