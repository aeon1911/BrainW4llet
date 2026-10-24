import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

import '../network/wallet_network.dart';

/// Moedas no modelo UTXO suportadas (mesmo fluxo: PSBT → assinatura).
enum UtxoCoin {
  bitcoin('BTC', 'Bitcoin', 'btc', 'sat/vB'),
  dash('DASH', 'Dash', 'dash', 'duff/B');

  const UtxoCoin(this.ticker, this.name, this.fileTag, this.feeUnit);

  final String ticker;
  final String name;

  /// Prefixo dos nomes de arquivo e dos tipos de documento de transferência.
  final String fileTag;
  final String feeUnit;
}

/// Conta UTXO derivada de uma chave pública estendida. A carteira online só
/// conhece essa chave pública e deriva os endereços a partir dela.
sealed class UtxoAccount {
  UtxoAccount(this.accountKey, this.network);

  /// Receber = cadeia 0; troco = cadeia 1.
  static const int receiveChain = 0;
  static const int changeChain = 1;

  final String accountKey;
  final WalletNetwork network;

  UtxoCoin get coin;

  /// Rede usada para converter scripts em endereços e vice-versa.
  BasedUtxoNetwork get addressNetwork;

  /// Tipo de script dos endereços desta conta.
  BitcoinAddressType get scriptType;

  /// Abaixo disso uma saída é "poeira" e a rede rejeita.
  BigInt get dustLimit;

  /// Taxa considerada anormal (na unidade [UtxoCoin.feeUnit]).
  int get alarmingFeeRate;

  /// Tamanho estimado (vB para SegWit, bytes para legado).
  int estimateSize(int inputs, int outputs);

  String address(int chain, int index);

  String path(int chain, int index);

  /// Converte texto em endereço desta rede (lança se inválido).
  BitcoinBaseAddress parseAddress(String text);

  static Bip44Changes chainOf(int chain) =>
      chain == changeChain ? Bip44Changes.chainInt : Bip44Changes.chainExt;

  static UtxoAccount forCoin(
    UtxoCoin coin,
    String accountKey,
    WalletNetwork network,
  ) => switch (coin) {
    UtxoCoin.bitcoin => BtcAccount(accountKey, network),
    UtxoCoin.dash => DashAccount(accountKey, network),
  };

  /// Chave privada de um endereço (lado frio). Quem chama zera o retorno.
  static List<int> privateKeyFromSeed(
    UtxoCoin coin,
    List<int> seed,
    WalletNetwork network,
    int chain,
    int index,
  ) => switch (coin) {
    UtxoCoin.bitcoin => BtcAccount.privateKeyFromSeed(
      seed,
      network,
      chain,
      index,
    ),
    UtxoCoin.dash => DashAccount.privateKeyFromSeed(seed, chain, index),
  };

  /// Script de bloqueio que a chave pública controla nesta moeda.
  static Script scriptForPublicKey(UtxoCoin coin, ECPublic publicKey) =>
      switch (coin) {
        UtxoCoin.bitcoin => publicKey.toSegwitAddress().toScriptPubKey(),
        UtxoCoin.dash => publicKey.toAddress().toScriptPubKey(),
      };

  static int estimateSizeFor(UtxoCoin coin, int inputs, int outputs) =>
      switch (coin) {
        UtxoCoin.bitcoin => BtcAccount.estimateP2wpkhSize(inputs, outputs),
        UtxoCoin.dash => DashAccount.estimateP2pkhSize(inputs, outputs),
      };

  static int alarmingFeeRateFor(UtxoCoin coin) => switch (coin) {
    UtxoCoin.bitcoin => 300,
    UtxoCoin.dash => 50,
  };

  static BasedUtxoNetwork addressNetworkFor(
    UtxoCoin coin,
    WalletNetwork network,
  ) => switch (coin) {
    UtxoCoin.bitcoin => BtcAccount.btcNetworkFor(network),
    UtxoCoin.dash => DashNetwork.mainnet,
  };
}

/// Conta Bitcoin SegWit nativa (BIP-84).
final class BtcAccount extends UtxoAccount {
  BtcAccount(super.accountKey, super.network)
    : _account = Bip84.fromExtendedKey(accountKey, coinFor(network));

  final Bip84 _account;

  @override
  UtxoCoin get coin => UtxoCoin.bitcoin;

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

  @override
  BasedUtxoNetwork get addressNetwork => btcNetwork;

  @override
  BitcoinAddressType get scriptType => SegwitAddressType.p2wpkh;

  @override
  BigInt get dustLimit => BigInt.from(294);

  @override
  int get alarmingFeeRate => 300;

  @override
  int estimateSize(int inputs, int outputs) =>
      estimateP2wpkhSize(inputs, outputs);

  static int estimateP2wpkhSize(int inputs, int outputs) =>
      (10.5 + 68 * inputs + 31 * outputs).ceil();

  @override
  String address(int chain, int index) => _account
      .change(UtxoAccount.chainOf(chain))
      .addressIndex(index)
      .publicKey
      .toAddress;

  @override
  String path(int chain, int index) {
    final coinType = network == WalletNetwork.mainnet ? 0 : 1;
    return "m/84'/$coinType'/0'/$chain/$index";
  }

  @override
  BitcoinBaseAddress parseAddress(String text) =>
      BitcoinAddress(text.trim(), network: btcNetwork).baseAddress;

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
      .change(UtxoAccount.chainOf(chain))
      .addressIndex(index)
      .privateKey
      .raw;
}

/// Conta Dash (BIP-44, P2PKH legado, endereços "X…"). Só rede principal:
/// não há servidor público de testnet Dash disponível.
final class DashAccount extends UtxoAccount {
  DashAccount(super.accountKey, super.network)
    : _account = Bip44.fromExtendedKey(accountKey, Bip44Coins.dash);

  final Bip44 _account;

  @override
  UtxoCoin get coin => UtxoCoin.dash;

  @override
  BasedUtxoNetwork get addressNetwork => DashNetwork.mainnet;

  @override
  BitcoinAddressType get scriptType => P2pkhAddressType.p2pkh;

  /// Mesmo limite de poeira do Dash Core para P2PKH.
  @override
  BigInt get dustLimit => BigInt.from(546);

  /// A rede Dash quase nunca congestiona: 1 duff/B é o padrão.
  @override
  int get alarmingFeeRate => 50;

  @override
  int estimateSize(int inputs, int outputs) =>
      estimateP2pkhSize(inputs, outputs);

  static int estimateP2pkhSize(int inputs, int outputs) =>
      10 + 148 * inputs + 34 * outputs;

  @override
  String address(int chain, int index) => _account
      .change(UtxoAccount.chainOf(chain))
      .addressIndex(index)
      .publicKey
      .toAddress;

  @override
  String path(int chain, int index) => "m/44'/5'/0'/$chain/$index";

  @override
  BitcoinBaseAddress parseAddress(String text) =>
      DashAddress(text.trim(), network: DashNetwork.mainnet).baseAddress;

  /// Chave privada de um endereço (lado frio). Quem chama zera o retorno.
  static List<int> privateKeyFromSeed(List<int> seed, int chain, int index) =>
      Bip44.fromSeed(seed, Bip44Coins.dash).purpose.coin
          .account(0)
          .change(UtxoAccount.chainOf(chain))
          .addressIndex(index)
          .privateKey
          .raw;
}
