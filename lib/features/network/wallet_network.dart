/// Rede em que a carteira opera. `testnet` usa redes de teste gratuitas
/// (BTC testnet4, Ethereum Sepolia, Solana devnet) para experimentar o fluxo
/// completo sem dinheiro de verdade.
enum WalletNetwork {
  mainnet('Principal (dinheiro real)'),
  testnet('Teste (sem valor)');

  const WalletNetwork(this.label);

  final String label;

  static WalletNetwork parse(Object? value) => WalletNetwork.values.firstWhere(
    (n) => n.name == value,
    orElse: () => throw const FormatException('Rede desconhecida.'),
  );
}
