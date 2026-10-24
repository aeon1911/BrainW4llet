import '../btc/btc_account.dart';
import 'watch_only.dart';

/// Onde um endereço foi encontrado na carteira.
final class AddressOwnership {
  const AddressOwnership(this.description);

  final String description;
}

/// Confere, no assinador frio, se um endereço mostrado pela carteira online
/// é mesmo desta seed. Protege contra uma máquina online comprometida (ou
/// um arquivo somente-leitura adulterado) que exiba o endereço de outra
/// pessoa para você receber.
///
/// [wallet] deve ser derivada da seed nesta sessão, nunca lida de arquivo.
AddressOwnership? findAddress(
  WatchOnlyWallet wallet,
  String address, {
  int scanPerChain = 500,
}) {
  final candidate = address.trim();
  if (candidate.isEmpty) return null;
  if (candidate.toLowerCase() == wallet.ethAddress.toLowerCase()) {
    return const AddressOwnership('Ethereum / EVM (m/44\'/60\'/0\'/0/0)');
  }
  if (candidate == wallet.solAddress) {
    return const AddressOwnership('Solana (m/44\'/501\'/0\'/0\')');
  }
  if (candidate == wallet.xmrAddress) {
    return const AddressOwnership('Monero (endereço principal)');
  }
  final accounts = <(UtxoAccount, String)>[
    (BtcAccount(wallet.btcAccountKey, wallet.network), candidate.toLowerCase()),
    if (wallet.dashAccountKey case final dashKey?)
      // Endereços Dash (Base58) diferenciam maiúsculas: comparação exata.
      (DashAccount(dashKey, wallet.network), candidate),
  ];
  for (final (account, target) in accounts) {
    for (final chain in [UtxoAccount.receiveChain, UtxoAccount.changeChain]) {
      for (var index = 0; index < scanPerChain; index++) {
        if (account.address(chain, index) == target) {
          final kind = chain == UtxoAccount.receiveChain
              ? 'recebimento'
              : 'troco';
          return AddressOwnership(
            '${account.coin.name}, $kind nº $index '
            '(${account.path(chain, index)})',
          );
        }
      }
    }
  }
  return null;
}
