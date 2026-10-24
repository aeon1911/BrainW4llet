import '../../features/btc/btc_account.dart';
import '../../features/btc/esplora_client.dart';
import '../../features/evm/evm_client.dart';
import '../../features/network/endpoints.dart';
import '../../features/network/http_json.dart';
import '../../features/sol/sol_client.dart';
import '../../features/wallet/watch_only.dart';

/// Clientes de rede da carteira online, criados a partir do arquivo
/// somente-leitura. Nenhum deles tem acesso a chaves privadas.
final class OnlineServices {
  OnlineServices(this.wallet)
    : endpoints = Endpoints.defaults(wallet.network),
      btcAccount = BtcAccount(wallet.btcAccountKey, wallet.network) {
    esplora = EsploraClient(endpoints.btcEsplora, http);
    evm = EvmClient(
      rpc: endpoints.evmRpc,
      blockscout: endpoints.evmBlockscout,
      chainId: endpoints.evmChainId,
      http: http,
    );
    sol = SolClient(endpoints.solRpc, http);
  }

  final WatchOnlyWallet wallet;
  final Endpoints endpoints;
  final BtcAccount btcAccount;
  final HttpJson http = HttpJson();
  late final EsploraClient esplora;
  late final EvmClient evm;
  late final SolClient sol;

  void close() => http.close();
}
