import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../network/wallet_network.dart';

/// Conta Bitcoin SegWit nativa (BIP-84). A carteira online só conhece a
/// chave pública da conta (zpub/vpub) e deriva os endereços a partir dela.
final class BtcAccount {
  BtcAccount(this.accountKey, this.network)
    : _account = Bip84.fromExtendedKey(accountKey, coinFor(network));

  /// Receber = cadeia 0; troco = cadeia 1.
  static const int receiveChain = 0;
  static const int changeChain = 1;

  final String accountKey;
  final WalletNetwork network;
  final Bip84 _account;

  static Bip84Coins coinFor(WalletNetwork network) => switch (network) {
    WalletNetwork.mainnet => Bip84Coins.bitcoin,
    WalletNetwork.testnet => Bip84Coins.bitcoinTestnet,
  };

  static BitcoinNetwork btcNetworkFor(WalletNetwork network) =>
      switch (network) {
        WalletNetwork.mainnet => BitcoinNetwork.mainnet,
        WalletNetwork.testnet => BitcoinNetwork.testnet4,
      };

  BitcoinNetwork get btcNetwork => btcNetworkFor(network);

  static Bip44Changes _chain(int chain) =>
      chain == changeChain ? Bip44Changes.chainInt : Bip44Changes.chainExt;

  String address(int chain, int index) =>
      _account.change(_chain(chain)).addressIndex(index).publicKey.toAddress;

  /// Caminho legível, para revisão no assinador.
  String path(int chain, int index) {
    final coin = network == WalletNetwork.mainnet ? 0 : 1;
    return "m/84'/$coin'/0'/$chain/$index";
  }

  /// Chave pública da conta a partir da seed (lado frio).
  static String accountKeyFromSeed(List<int> seed, WalletNetwork network) =>
      Bip84.fromSeed(
        seed,
        coinFor(network),
      ).purpose.coin.account(0).publicKey.toExtended;

  /// Chave privada de um endereço (lado frio). Quem chama zera o retorno.
  static List<int> privateKeyFromSeed(
    List<int> seed,
    WalletNetwork network,
    int chain,
    int index,
  ) => Bip84.fromSeed(seed, coinFor(network)).purpose.coin
      .account(0)
      .change(_chain(chain))
      .addressIndex(index)
      .privateKey
      .raw;
}
