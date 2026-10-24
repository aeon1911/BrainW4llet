import 'wallet_network.dart';

/// Servidores públicos usados pela carteira online. Eles veem os endereços
/// consultados e o IP de quem consulta; troque por nós próprios se quiser
/// mais privacidade.
final class Endpoints {
  const Endpoints({
    required this.btcEsplora,
    required this.btcExplorerTx,
    required this.evmRpc,
    required this.evmChainId,
    required this.evmBlockscout,
    required this.evmExplorerTx,
    required this.solRpc,
    required this.solExplorerTx,
    required this.solExplorerSuffix,
  });

  /// API Esplora (mempool.space).
  final Uri btcEsplora;
  final String btcExplorerTx;

  /// JSON-RPC Ethereum.
  final Uri evmRpc;
  final int evmChainId;

  /// API v2 do Blockscout (histórico de transações).
  final Uri evmBlockscout;
  final String evmExplorerTx;

  /// JSON-RPC Solana.
  final Uri solRpc;
  final String solExplorerTx;
  final String solExplorerSuffix;

  static Endpoints defaults(WalletNetwork network) => switch (network) {
    WalletNetwork.mainnet => Endpoints(
      btcEsplora: Uri.parse('https://mempool.space/api'),
      btcExplorerTx: 'https://mempool.space/tx/',
      evmRpc: Uri.parse('https://ethereum-rpc.publicnode.com'),
      evmChainId: 1,
      evmBlockscout: Uri.parse('https://eth.blockscout.com/api/v2'),
      evmExplorerTx: 'https://etherscan.io/tx/',
      solRpc: Uri.parse('https://api.mainnet-beta.solana.com'),
      solExplorerTx: 'https://solscan.io/tx/',
      solExplorerSuffix: '',
    ),
    WalletNetwork.testnet => Endpoints(
      btcEsplora: Uri.parse('https://mempool.space/testnet4/api'),
      btcExplorerTx: 'https://mempool.space/testnet4/tx/',
      evmRpc: Uri.parse('https://ethereum-sepolia-rpc.publicnode.com'),
      evmChainId: 11155111,
      evmBlockscout: Uri.parse('https://eth-sepolia.blockscout.com/api/v2'),
      evmExplorerTx: 'https://sepolia.etherscan.io/tx/',
      solRpc: Uri.parse('https://api.devnet.solana.com'),
      solExplorerTx: 'https://solscan.io/tx/',
      solExplorerSuffix: '?cluster=devnet',
    ),
  };
}
