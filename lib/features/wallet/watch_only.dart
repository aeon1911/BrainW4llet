import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:sodium/sodium_sumo.dart';

import '../btc/btc_account.dart';
import '../network/wallet_network.dart';
import '../xmr/xmr_keys.dart';

/// Um dado exportado para a carteira somente-leitura.
final class WatchOnlyField {
  const WatchOnlyField(this.label, this.value, {this.sensitive = false});

  final String label;
  final String value;

  /// Não permite gastar, mas revela saldo/histórico (ex.: view key do Monero).
  final bool sensitive;
}

/// Tudo o que uma carteira watch-only precisa para mostrar o saldo de uma
/// moeda, sem poder gastar nada.
final class WatchOnlyAsset {
  const WatchOnlyAsset({
    required this.name,
    required this.ticker,
    required this.path,
    required this.fields,
    required this.howToWatch,
  });

  final String name;
  final String ticker;
  final String path;
  final List<WatchOnlyField> fields;
  final String howToWatch;
}

/// Caminhos de derivação. Mudar qualquer um muda os endereços: depois que
/// houver fundos, estes valores ficam congelados.
abstract final class WatchOnlyPaths {
  static const bitcoinAccount = "m/84'/0'/0'";
  static const ethereum = "m/44'/60'/0'/0/0";
  static const solana = "m/44'/501'/0'/0'";
  static const dashAccount = "m/44'/5'/0'";
  static const monero = "m/44'/128'/0'/0/0";
}

/// Arquivo da carteira somente-leitura (equivalente ao "watching-only
/// wallet" do Electrum): tudo o que a carteira online precisa para ver
/// saldos, gerar endereços de recebimento e montar transações, sem nenhuma
/// chave que permita gastar.
final class WatchOnlyWallet {
  const WatchOnlyWallet({
    required this.network,
    required this.btcAccountKey,
    required this.ethAddress,
    required this.solAddress,
    this.dashAccountKey,
    this.xmrAddress,
    this.xmrViewKey,
    this.createdAt,
  });

  static const String format = 'brainw4llet-watch-only';
  static const int version = 1;

  final WalletNetwork network;
  final String btcAccountKey;
  final String ethAddress;
  final String solAddress;

  /// Dash e Monero só existem na rede principal (fases seguintes).
  final String? dashAccountKey;
  final String? xmrAddress;
  final String? xmrViewKey;

  /// Quando o arquivo foi gerado (relógio do assinador). A carteira online
  /// usa como ponto de partida da varredura do Monero. Não entra na
  /// impressão digital.
  final DateTime? createdAt;

  /// Deriva tudo a partir da seed BIP-39 de 64 bytes (lado frio).
  ///
  /// Limitação: a `blockchain_utils` mantém cópias das chaves no heap do
  /// Dart enquanto deriva (ver core/security/README.md).
  factory WatchOnlyWallet.fromSeed(SecureKey seed, WalletNetwork network) =>
      seed.runUnlockedSync((bytes) {
        final mainnet = network == WalletNetwork.mainnet;
        // Monero na rede principal e na stagenet (rede de teste).
        final xmr = XmrKeys.fullAccount(bytes, network);
        final xmrAddress = xmr.primaryAddress;
        final xmrViewKey = BytesUtils.toHexString(xmr.privateViewKey.raw);
        return WatchOnlyWallet(
          network: network,
          btcAccountKey: BtcAccount.accountKeyFromSeed(bytes, network),
          ethAddress: Bip44.fromSeed(
            bytes,
            Bip44Coins.ethereum,
          ).deriveDefaultPath.publicKey.toAddress,
          // Não use deriveDefaultPath: na blockchain_utils ele para em
          // m/44'/501'/0', e o Phantom/Solflare usam m/44'/501'/0'/0'
          // (ed25519 SLIP-10 endurece todos os níveis).
          solAddress: Bip44.fromSeed(bytes, Bip44Coins.solana).purpose.coin
              .account(0)
              .change(Bip44Changes.chainExt)
              .publicKey
              .toAddress,
          dashAccountKey: mainnet
              ? Bip44.fromSeed(
                  bytes,
                  Bip44Coins.dash,
                ).purpose.coin.account(0).publicKey.toExtended
              : null,
          xmrAddress: xmrAddress,
          xmrViewKey: xmrViewKey,
          createdAt: DateTime.now().toUtc(),
        );
      });

  factory WatchOnlyWallet.fromJson(Map<String, Object?> json) {
    if (json['format'] != format) {
      throw const FormatException('Não é um arquivo de carteira BrainW4llet.');
    }
    if (json['version'] != version) {
      throw const FormatException('Versão do arquivo não suportada.');
    }
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Campo "$key" ausente no arquivo.');
      }
      return value;
    }

    String? optional(String key) =>
        json[key] is String ? json[key]! as String : null;

    final wallet = WatchOnlyWallet(
      network: WalletNetwork.parse(json['network']),
      btcAccountKey: required('btcAccountKey'),
      ethAddress: required('ethAddress'),
      solAddress: required('solAddress'),
      dashAccountKey: optional('dashAccountKey'),
      xmrAddress: optional('xmrAddress'),
      xmrViewKey: optional('xmrViewKey'),
      createdAt: DateTime.tryParse(optional('createdAt') ?? ''),
    );
    // Valida as chaves de verdade (lança se a zpub/vpub for inválida).
    BtcAccount(wallet.btcAccountKey, wallet.network);
    return wallet;
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'network': network.name,
    'btcAccountKey': btcAccountKey,
    'ethAddress': ethAddress,
    'solAddress': solAddress,
    if (dashAccountKey != null) 'dashAccountKey': dashAccountKey,
    if (xmrAddress != null) 'xmrAddress': xmrAddress,
    if (xmrViewKey != null) 'xmrViewKey': xmrViewKey,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  /// Impressão digital curta para conferir que é sempre a mesma carteira.
  String get fingerprint {
    // Cobre todos os campos: qualquer alteração no arquivo muda a impressão.
    final hash = QuickCrypto.sha256Hash(
      utf8.encode(
        [
          network.name,
          btcAccountKey,
          ethAddress,
          solAddress,
          dashAccountKey ?? '',
          xmrAddress ?? '',
          xmrViewKey ?? '',
        ].join('|'),
      ),
    );
    final hex = BytesUtils.toHexString(hash.sublist(0, 4)).toUpperCase();
    return '${hex.substring(0, 4)}-${hex.substring(4)}';
  }

  /// Dados para exibição, um cartão por moeda.
  List<WatchOnlyAsset> get assets {
    final btc = BtcAccount(btcAccountKey, network);
    final testnet = network == WalletNetwork.testnet;
    return [
      WatchOnlyAsset(
        name: testnet ? 'Bitcoin (testnet4)' : 'Bitcoin',
        ticker: 'BTC',
        path:
            '${testnet ? "m/84'/1'/0'" : WatchOnlyPaths.bitcoinAccount} '
            '(SegWit nativo)',
        fields: [
          WatchOnlyField(
            testnet
                ? 'Chave pública da conta (vpub)'
                : 'Chave pública da conta (zpub)',
            btcAccountKey,
          ),
          WatchOnlyField(
            'Primeiro endereço de recebimento',
            btc.address(UtxoAccount.receiveChain, 0),
          ),
        ],
        howToWatch:
            'Sparrow (PC), BlueWallet ou Nunchuk (celular): nova carteira '
            '→ "somente leitura"/watch-only → cole a zpub. Mostra o saldo '
            'de todos os endereços.',
      ),
      WatchOnlyAsset(
        name: testnet ? 'Ethereum (Sepolia)' : 'Ethereum e redes EVM',
        ticker: 'ETH',
        path: WatchOnlyPaths.ethereum,
        fields: [WatchOnlyField('Endereço', ethAddress)],
        howToWatch:
            'O mesmo endereço vale em Ethereum, Polygon, BSC, Arbitrum, '
            'Base etc., inclusive para tokens. Rabby: "adicionar endereço '
            'para observar"; ou pesquise no etherscan.io / debank.com.',
      ),
      WatchOnlyAsset(
        name: testnet ? 'Solana (devnet)' : 'Solana',
        ticker: 'SOL',
        path: WatchOnlyPaths.solana,
        fields: [WatchOnlyField('Endereço', solAddress)],
        howToWatch:
            'Mesmo caminho do Phantom e do Solflare. Pesquise o endereço '
            'no solscan.io ou adicione como "watch wallet" no Solflare.',
      ),
      if (dashAccountKey case final dashKey?)
        WatchOnlyAsset(
          name: 'Dash',
          ticker: 'DASH',
          path: WatchOnlyPaths.dashAccount,
          fields: [
            WatchOnlyField('Chave pública da conta (xpub)', dashKey),
            WatchOnlyField(
              'Primeiro endereço de recebimento',
              Bip44.fromExtendedKey(dashKey, Bip44Coins.dash)
                  .change(Bip44Changes.chainExt)
                  .addressIndex(0)
                  .publicKey
                  .toAddress,
            ),
          ],
          howToWatch:
              'Dash Electrum: nova carteira → "usar uma chave mestra" → cole '
              'a xpub. Ou pesquise o endereço no insight.dash.org.',
        ),
      if ((xmrAddress, xmrViewKey) case (final address?, final viewKey?))
        WatchOnlyAsset(
          name: testnet ? 'Monero (stagenet)' : 'Monero',
          ticker: 'XMR',
          path: '${WatchOnlyPaths.monero} (secp256k1 → Keccak → ed25519)',
          fields: [
            WatchOnlyField('Endereço principal', address),
            WatchOnlyField(
              'Chave privada de visualização (view key)',
              viewKey,
              sensitive: true,
            ),
          ],
          howToWatch:
              'Feather Wallet: criar carteira → "restaurar somente '
              'visualização" → endereço + view key + data de criação (hoje). '
              'A view key não gasta, mas revela saldo e entradas: trate como '
              'dado privado.',
        ),
    ];
  }
}

/// Dados públicos de BTC, ETH/EVM, SOL, DASH e XMR na rede principal.
List<WatchOnlyAsset> deriveWatchOnly(SecureKey seed) =>
    WatchOnlyWallet.fromSeed(seed, WalletNetwork.mainnet).assets;
