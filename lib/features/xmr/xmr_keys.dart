import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:monero_dart/monero_dart.dart';

import '../../core/security/memory.dart';
import '../network/wallet_network.dart';

/// Chaves Monero da carteira.
///
/// Derivação (ver core/security/README.md): chave BIP-44 secp256k1 em
/// m/44'/128'/0'/0/0 → spend = sc_reduce(Keccak256(priv)),
/// view = sc_reduce(Keccak256(spend)). A rede de teste usa a stagenet.
abstract final class XmrKeys {
  static MoneroCoins coinFor(WalletNetwork network) => switch (network) {
    WalletNetwork.mainnet => MoneroCoins.moneroMainnet,
    WalletNetwork.testnet => MoneroCoins.moneroStagenet,
  };

  static MoneroNetwork networkFor(WalletNetwork network) => switch (network) {
    WalletNetwork.mainnet => MoneroNetwork.mainnet,
    WalletNetwork.testnet => MoneroNetwork.stagenet,
  };

  /// Conta completa, com a chave de gasto (só no assinador frio).
  static MoneroAccount fullAccount(List<int> seed, WalletNetwork network) {
    final bip44Key = Bip44.fromSeed(
      seed,
      Bip44Coins.moneroSecp256k1,
    ).deriveDefaultPath.privateKey.raw;
    try {
      return MoneroAccount.fromBip44PrivateKey(
        bip44Key,
        coinType: coinFor(network),
      );
    } finally {
      wipeBytes(bip44Key);
    }
  }

  /// Conta somente-leitura: view key + chave pública de gasto (do endereço).
  /// Encontra entradas e valores, mas não gasta nem calcula key images.
  static MoneroAccount watchAccount({
    required String address,
    required String viewKeyHex,
    required WalletNetwork network,
  }) {
    final parsed = MoneroAddress(address);
    if (parsed.network != networkFor(network)) {
      throw const FormatException('Endereço Monero de outra rede.');
    }
    return MoneroAccount.fromWatchOnly(
      BytesUtils.fromHexString(viewKeyHex),
      parsed.pubSpendKey,
      coinType: coinFor(network),
    );
  }

  static MoneroAccountKeys keys(MoneroAccount account, WalletNetwork network) =>
      MoneroAccountKeys(account: account, network: networkFor(network));
}
