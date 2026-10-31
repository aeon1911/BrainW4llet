import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/btc/btc_account.dart';
import '../../features/btc/btc_wallet_state.dart';
import '../../features/btc/esplora_client.dart';
import '../../features/network/http_json.dart';
import '../../features/wallet/watch_only.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../theme/app_theme.dart';
import '../theme/coins.dart';
import '../widgets/page_frame.dart';
import '../widgets/ui.dart';
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
    try {
      final text = await pickTextFile(context);
      if (text == null) return;
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
    final coins = [
      CoinStyle.btc,
      CoinStyle.eth,
      CoinStyle.sol,
      if (services.hasDash) CoinStyle.dash,
      if (_hasXmr(services)) CoinStyle.xmr,
    ];
    final p = AppPalette.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    void broadcast() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BroadcastScreen(services: services),
      ),
    );
    return DefaultTabController(
      length: coins.length,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          titleSpacing: 20,
          title: Row(
            children: [
              const BrandMark(size: 32),
              const SizedBox(width: 12),
              const Text('Carteira'),
              const SizedBox(width: 10),
              Flexible(
                child: Pill(
                  wallet.fingerprint,
                  icon: Icons.fingerprint_rounded,
                  color: p.muted,
                ),
              ),
              if (wallet.network.name == 'testnet') ...[
                const SizedBox(width: 8),
                Pill('Teste', icon: Icons.science_outlined, color: p.warning),
              ],
            ],
          ),
          actions: [
            if (wide)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.cell_tower_rounded, size: 18),
                  label: const Text('Transmitir'),
                  onPressed: broadcast,
                ),
              )
            else
              IconButton(
                tooltip: 'Transmitir transação assinada',
                icon: const Icon(Icons.cell_tower_rounded),
                onPressed: broadcast,
              ),
            IconButton(
              tooltip: 'Fechar carteira',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => setState(() {
                _services?.close();
                _services = null;
              }),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Align(
              alignment: wide ? Alignment.center : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final coin in coins)
                      Tab(
                        height: 44,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CoinAvatar(coin, size: 22),
                            const SizedBox(width: 8),
                            Text(coin.label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            if (wallet.network.name == 'testnet')
              Container(
                width: double.infinity,
                color: p.warning.withValues(alpha: 0.10),
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Rede de TESTE: moedas sem valor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.warning,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
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
    final p = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Carteira online')),
      body: PageFrame(
        children: [
          const SizedBox(height: 12),
          IconBadge(Icons.account_balance_wallet_outlined, size: 56),
          const SizedBox(height: 20),
          Text(
            'Abra sua carteira\nsomente leitura',
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.15),
          ),
          const SizedBox(height: 10),
          Text(
            'Abra o arquivo "carteira-somente-leitura-….json" salvo pelo '
            'assinador frio. Ele permite ver saldos, receber e montar envios, '
            'mas não contém nenhuma chave capaz de gastar.',
            style: theme.textTheme.bodyLarge?.copyWith(color: p.muted),
          ),
          const SizedBox(height: 24),
          AppCard(
            onTap: _open,
            glow: p.accent,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Column(
              children: [
                Icon(Icons.upload_file_rounded, size: 36, color: p.accent),
                const SizedBox(height: 12),
                Text(
                  'Abrir arquivo da carteira',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'carteira-somente-leitura-XXXX.json',
                  style: AppTheme.mono(fontSize: 12, color: p.faint),
                ),
              ],
            ),
          ),
          if (_error != null) Notice(kind: NoticeKind.danger, text: _error),
          const SizedBox(height: 8),
          Notice(
            kind: NoticeKind.info,
            title: 'Servidores públicos',
            text:
                'mempool.space (BTC; se ele não responder, mempool.emzy.de e '
                'mempool.bullbitcoin.com), publicnode.com e Blockscout (ETH), '
                'RPC oficial da Solana, Insight (Dash) e um nó Monero. Eles '
                'veem os endereços consultados e o seu IP. A detecção das '
                'suas moedas Monero acontece neste computador.',
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
    coin: CoinStyle.fromTicker(account.coin.ticker)!,
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
    coin: CoinStyle.eth,
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
    coin: CoinStyle.sol,
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
