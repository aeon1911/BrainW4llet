import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:sodium/sodium_sumo.dart';

/// Primeiros endereços de recebimento, para conferir a derivação contra
/// outra carteira (watch-only) importando a mesma seed + passphrase.
///
/// Limitação: a `blockchain_utils` mantém cópias das chaves no heap do Dart
/// enquanto deriva; elas não podem ser zeradas (ver core/security/README.md).
final class AddressPreview {
  const AddressPreview({required this.ethereum, required this.bitcoin});

  /// Derivado a partir de um seed BIP-39 de 64 bytes.
  factory AddressPreview.fromSeed(SecureKey seed) =>
      seed.runUnlockedSync((bytes) {
        return AddressPreview(
          ethereum: Bip44.fromSeed(
            bytes,
            Bip44Coins.ethereum,
          ).deriveDefaultPath.publicKey.toAddress,
          bitcoin: Bip84.fromSeed(
            bytes,
            Bip84Coins.bitcoin,
          ).deriveDefaultPath.publicKey.toAddress,
        );
      });

  static const String ethereumPath = "m/44'/60'/0'/0/0";
  static const String bitcoinPath = "m/84'/0'/0'/0/0";

  final String ethereum;
  final String bitcoin;
}
