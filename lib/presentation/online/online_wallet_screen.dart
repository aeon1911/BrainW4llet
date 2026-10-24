import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/btc/btc_account.dart';
import '../../features/btc/btc_wallet_state.dart';
import '../../features/btc/esplora_client.dart';
import '../../features/network/http_json.dart';
import '../../features/wallet/watch_only.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../widgets/page_frame.dart';
import 'broadcast_screen.dart';
import 'chain_tab.dart';
import 'online_services.dart';
import 'send_screens.dart';
import 'xmr_tab.dart';

/// Carteira online (somente leitura): saldo, histórico, receber, montar
/// envios e transmitir transações assinadas. Não tem nenhuma chave privada.
class OnlineWalletScreen extends StatefulWidget {
  const OnlineWalletScreen({super.key});

  @override
  State<OnlineWalletScreen> createState() => _OnlineWalletScreenState();
}

class _OnlineWalletScreenState extends State<OnlineWalletScreen> {
  OnlineServices? _services;
  String? _error;

  @override
  void dispose() {
    _services?.close();
    super.dispose();
  }

  Future<void> _open() async {
    final text = await pickTextFile();
    if (text == null) return;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        throw const FormatException('Arquivo inválido.');
      }
      final wallet = WatchOnlyWallet.fromJson(json);
      setState(() {
        _services?.close();
        _services = OnlineServices(wallet);
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Arquivo de carteira inválido: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services == null) return _openScreen(context);
    final wallet = services.wallet;
    return DefaultTabController(
      length: 3 + (services.hasDash ? 1 : 0) + (_hasXmr(services) ? 1 : 0),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Carteira ${wallet.fingerprint}'),
          actions: [
            IconButton(
              tooltip: 'Transmitir transação assinada',
              icon: const Icon(Icons.upload_file),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BroadcastScreen(services: services),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Fechar carteira',
              icon: const Icon(Icons.logout),
              onPressed: () => setState(() {
                _services?.close();
                _services = null;
              }),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Bitcoin'),
              Tab(text: 'Ethereum'),
              Tab(text: 'Solana'),
              if (services.hasDash) Tab(text: 'Dash'),
              if (_hasXmr(services)) Tab(text: 'Monero'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (wallet.network.name == 'testnet')
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                padding: const EdgeInsets.all(6),
                child: const Text(
                  'Rede de TESTE: moedas sem valor.',
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _btcTab(services),
                  _evmTab(services),
                  _solTab(services),
                  if (services.hasDash) _dashTab(services),
                  if (_hasXmr(services)) XmrTab(services: services),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _openScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Carteira online')),
      body: PageFrame(
        children: [
          Text(
            'Abra o arquivo "carteira-somente-leitura-….json" salvo pelo '
            'assinador frio. Ele permite ver saldos, receber e montar envios, '
            'mas não contém nenhuma chave capaz de gastar.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.file_open),
            label: const Text('Abrir arquivo da carteira'),
            onPressed: _open,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Text(
            'Servidores públicos usados: mempool.space (BTC), publicnode.com e '
            'Blockscout (ETH), RPC oficial da Solana. Eles veem os endereços '
            'consultados e o seu IP.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  bool _hasXmr(OnlineServices services) =>
      services.wallet.xmrAddress != null && services.wallet.xmrViewKey != null;

  Widget _btcTab(OnlineServices services) => _utxoTab(
    account: services.btcAccount,
    backend: services.esplora,
    explorerTx: services.endpoints.btcExplorerTx,
    explorerSuffix: '',
    feeOptions: () async {
      final rates = await services.esplora.feeRates();
      return [
        ('Rápida', rates.fastest),
        ('~30 min', rates.halfHour),
        ('~1 hora', rates.hour),
        ('Econômica', rates.economy),
      ];
    },
  );

  Widget _dashTab(OnlineServices services) => _utxoTab(
    account: services.dashAccount!,
    backend: services.dash!,
    explorerTx: services.endpoints.dashExplorerTx!,
    explorerSuffix: services.endpoints.dashExplorerSuffix,
    // A rede Dash quase nunca congestiona: 1 duff/B é a taxa padrão.
    feeOptions: () async => const [('Normal', 1), ('Prioritária', 2)],
  );

  Widget _utxoTab({
    required UtxoAccount account,
    required UtxoBackend backend,
    required String explorerTx,
    required String explorerSuffix,
    required FeeOptions feeOptions,
  }) => ChainTab<BtcWalletState>(
    load: () async {
      final state = await BtcSync(account, backend).run();
      String fmt(BigInt v) => formatUtxo(account.coin, v);
      return ChainSnapshot(
        balance: fmt(state.confirmedBalance),
        pending: state.unconfirmedBalance == BigInt.zero
            ? null
            : 'Pendente: ${fmt(state.unconfirmedBalance)}',
        receiveAddress: account.address(
          UtxoAccount.receiveChain,
          state.nextReceive.index,
        ),
        receiveNote:
            'Um endereço novo a cada recebimento (privacidade). Antes de '
            'receber valores altos, confira-o no assinador frio '
            '("Conferir endereço").',
        history: [
          for (final h in state.history)
            HistoryRow(
              id: h.txid,
              amount: signed(fmt(h.delta.abs()), h.delta),
              incoming: !h.delta.isNegative,
              when: formatDate(h.time),
              explorerUrl: '$explorerTx${h.txid}$explorerSuffix',
            ),
        ],
        raw: state,
      );
    },
    onSend: (context, snapshot) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UtxoSendScreen(
          account: account,
          backend: backend,
          state: snapshot.raw,
          feeOptions: feeOptions,
        ),
      ),
    ),
  );

  Widget _evmTab(OnlineServices services) => ChainTab<BigInt>(
    load: () async {
      final address = services.wallet.ethAddress;
      final balance = await services.evm.balance(address);
      final url = services.endpoints.evmExplorerTx;
      String? historyError;
      var history = <HistoryRow>[];
      try {
        history = [
          for (final h in await services.evm.history(address))
            HistoryRow(
              id: h.hash,
              amount: signed(formatEth(h.delta.abs()), h.delta),
              incoming: !h.delta.isNegative,
              when: formatDate(h.time),
              explorerUrl: '$url${h.hash}',
              failed: h.failed,
            ),
        ];
      } on NetworkException catch (e) {
        historyError = 'Histórico indisponível agora ($e).';
      }
      return ChainSnapshot(
        balance: formatEth(balance),
        receiveAddress: address,
        receiveNote:
            'Mesmo endereço em todas as redes EVM. Confira-o no assinador '
            'frio antes de receber valores altos.',
        history: history,
        historyError: historyError,
        raw: balance,
      );
    },
    onSend: (context, snapshot) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EvmSendScreen(services: services, balance: snapshot.raw),
      ),
    ),
  );

  Widget _solTab(OnlineServices services) => ChainTab<BigInt>(
    load: () async {
      final address = services.wallet.solAddress;
      final balance = await services.sol.balance(address);
      final url = services.endpoints.solExplorerTx;
      final suffix = services.endpoints.solExplorerSuffix;
      String? historyError;
      var history = <HistoryRow>[];
      try {
        history = [
          for (final h in await services.sol.history(address))
            HistoryRow(
              id: h.signature,
              amount: h.delta == null
                  ? '?'
                  : signed(formatSol(h.delta!.abs()), h.delta!),
              incoming: !(h.delta?.isNegative ?? false),
              when: formatDate(h.time),
              explorerUrl: '$url${h.signature}$suffix',
              failed: h.failed,
            ),
        ];
      } on NetworkException catch (e) {
        historyError = 'Histórico indisponível agora ($e).';
      }
      return ChainSnapshot(
        balance: formatSol(balance),
        receiveAddress: address,
        receiveNote:
            'Confira-o no assinador frio antes de receber valores altos.',
        history: history,
        historyError: historyError,
        raw: balance,
      );
    },
    onSend: (context, snapshot) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SolSendScreen(services: services, balance: snapshot.raw),
      ),
    ),
  );
}
