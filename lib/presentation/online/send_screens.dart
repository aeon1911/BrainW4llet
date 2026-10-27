import 'package:flutter/material.dart';

import '../../features/btc/btc_send.dart';
import '../../features/btc/btc_wallet_state.dart';
import '../../features/btc/btc_account.dart';
import '../../features/btc/esplora_client.dart';
import '../../features/evm/evm_send.dart';
import '../../features/sol/sol_send.dart';
import '../../features/transfer/transfer_document.dart';
import '../../features/wallet/amounts.dart';
import '../theme/app_theme.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../widgets/page_frame.dart';
import '../widgets/ui.dart';
import 'online_services.dart';

/// Campos comuns: destino, valor e "enviar tudo".
class _SendFields extends StatelessWidget {
  const _SendFields({
    required this.destination,
    required this.amount,
    required this.sendAll,
    required this.onSendAll,
    required this.unit,
    required this.enabled,
  });

  final TextEditingController destination;
  final TextEditingController amount;
  final bool sendAll;
  final ValueChanged<bool> onSendAll;
  final String unit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: destination,
          enabled: enabled,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Endereço de destino'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          enabled: enabled && !sendAll,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Valor ($unit)'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enviar tudo (saldo menos a taxa)'),
          value: sendAll,
          onChanged: enabled ? onSendAll : null,
        ),
      ],
    );
  }
}

/// Salva o pedido e avisa o próximo passo.
Future<void> _saveRequest(
  BuildContext context,
  TransferDocument request,
) async {
  final path = await saveTextFile(request.suggestedFileName, request.encode());
  if (path == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Pedido salvo. Leve o arquivo ao assinador frio, assine e traga a '
        'transação assinada de volta para transmitir.',
      ),
      duration: Duration(seconds: 6),
    ),
  );
  Navigator.of(context).pop();
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.error);

  final String? error;

  @override
  Widget build(BuildContext context) => error == null
      ? const SizedBox.shrink()
      : Notice(kind: NoticeKind.danger, text: error);
}

/// Saldo disponível no topo das telas de envio.
class AvailableCard extends StatelessWidget {
  const AvailableCard(this.formatted, {super.key, this.label = 'Disponível'});

  final String formatted;
  final String label;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppPalette.of(context).muted)),
        const SizedBox(height: 4),
        AmountText(formatted, fontSize: 24),
      ],
    ),
  );
}

/// Resumo antes de criar o arquivo.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.rows, this.total, this.note});

  final List<(String, String)> rows;
  final (String, String)? total;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows) KeyValueRow(label, value),
          if (total != null) ...[
            Divider(color: p.outline),
            KeyValueRow(total!.$1, total!.$2, emphasis: true),
          ],
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note!, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------ Bitcoin e Dash --

/// Opções de taxa (rótulo, valor na unidade da moeda).
typedef FeeOptions = Future<List<(String, int)>> Function();

class UtxoSendScreen extends StatefulWidget {
  const UtxoSendScreen({
    super.key,
    required this.account,
    required this.backend,
    required this.state,
    required this.feeOptions,
  });

  final UtxoAccount account;
  final UtxoBackend backend;
  final BtcWalletState state;
  final FeeOptions feeOptions;

  @override
  State<UtxoSendScreen> createState() => _UtxoSendScreenState();
}

class _UtxoSendScreenState extends State<UtxoSendScreen> {
  final _destination = TextEditingController();
  final _amount = TextEditingController();
  final _customFee = TextEditingController();
  bool _sendAll = false;
  bool _busy = false;
  String? _error;
  List<(String, int)>? _rates;
  int? _feeRate;
  BtcSendPlan? _plan;

  UtxoCoin get _coin => widget.account.coin;

  String _fmt(BigInt units) => formatUtxo(_coin, units);

  @override
  void initState() {
    super.initState();
    widget
        .feeOptions()
        .then((rates) {
          if (mounted) {
            setState(() {
              _rates = rates;
              _feeRate = rates[rates.length > 1 ? 1 : 0].$2;
            });
          }
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() => _error = 'Não foi possível obter as taxas: $e');
          }
        });
  }

  @override
  void dispose() {
    _destination.dispose();
    _amount.dispose();
    _customFee.dispose();
    super.dispose();
  }

  void _review() {
    setState(() {
      _error = null;
      _plan = null;
    });
    try {
      final rate = _feeRate ?? int.tryParse(_customFee.text);
      if (rate == null) throw const BtcSendException('Escolha a taxa.');
      final plan = BtcSend.plan(
        state: widget.state,
        account: widget.account,
        destination: _destination.text,
        amount: _sendAll ? null : Amounts.parse(_amount.text, 8),
        feeRate: rate,
      );
      setState(() => _plan = plan);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on BtcSendException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final request = await BtcSend.buildRequest(
        plan: _plan!,
        state: widget.state,
        account: widget.account,
        rawTransaction: widget.backend.rawTransaction,
      );
      if (mounted) await _saveRequest(context, request);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rates = _rates;
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: Text('Enviar ${_coin.name}')),
      body: PageFrame(
        children: [
          AvailableCard(
            _fmt(widget.state.confirmedBalance),
            label: 'Saldo confirmado disponível',
          ),
          const SizedBox(height: 8),
          _SendFields(
            destination: _destination,
            amount: _amount,
            sendAll: _sendAll,
            onSendAll: (v) => setState(() {
              _sendAll = v;
              _plan = null;
            }),
            unit: _coin.ticker,
            enabled: !_busy,
          ),
          const SectionTitle('Taxa'),
          if (rates == null)
            const LinearProgressIndicator()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, rate) in rates)
                  ChoiceChip(
                    label: Text('$label · $rate ${_coin.feeUnit}'),
                    selected: _feeRate == rate,
                    onSelected: (_) => setState(() {
                      _feeRate = rate;
                      _plan = null;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Personalizada'),
                  selected: _feeRate == null,
                  onSelected: (_) => setState(() {
                    _feeRate = null;
                    _plan = null;
                  }),
                ),
              ],
            ),
          if (_feeRate == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customFee,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _coin.feeUnit),
            ),
          ],
          const SizedBox(height: 16),
          _ErrorText(_error),
          if (plan == null)
            FilledButton(
              onPressed: _busy || rates == null ? null : _review,
              child: const Text('Revisar'),
            )
          else ...[
            _PlanCard(
              rows: [
                ('Enviar', _fmt(plan.amount)),
                (
                  'Taxa',
                  '${_fmt(plan.fee)} (${plan.feeRate} ${_coin.feeUnit})',
                ),
                if (plan.change > BigInt.zero)
                  ('Troco (volta para você)', _fmt(plan.change)),
                ('Moedas usadas', '${plan.inputs.length}'),
              ],
              total: ('Total que sai', _fmt(plan.amount + plan.fee)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Criar arquivo para assinar'),
              onPressed: _busy ? null : _create,
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Ethereum --

class EvmSendScreen extends StatefulWidget {
  const EvmSendScreen({
    super.key,
    required this.services,
    required this.balance,
  });

  final OnlineServices services;
  final BigInt balance;

  @override
  State<EvmSendScreen> createState() => _EvmSendScreenState();
}

class _EvmSendScreenState extends State<EvmSendScreen> {
  final _destination = TextEditingController();
  final _amount = TextEditingController();
  bool _sendAll = false;
  bool _busy = false;
  String? _error;
  EvmSignRequest? _request;
  EvmReview? _review;

  @override
  void dispose() {
    _destination.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
      _request = null;
    });
    try {
      final request = await EvmSend.buildRequest(
        network: widget.services.wallet.network,
        from: widget.services.wallet.ethAddress,
        to: _destination.text,
        amount: _sendAll ? null : Amounts.parse(_amount.text, 18),
        client: widget.services.evm,
      );
      setState(() {
        _request = request;
        _review = EvmSend.review(request).$2;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar Ethereum')),
      body: PageFrame(
        children: [
          AvailableCard(formatEth(widget.balance), label: 'Saldo'),
          const SizedBox(height: 8),
          _SendFields(
            destination: _destination,
            amount: _amount,
            sendAll: _sendAll,
            onSendAll: (v) => setState(() {
              _sendAll = v;
              _request = null;
            }),
            unit: 'ETH',
            enabled: !_busy,
          ),
          _ErrorText(_error),
          if (_request == null || review == null)
            FilledButton(
              onPressed: _busy ? null : _prepare,
              child: _busy
                  ? const Text('Consultando taxa e nonce…')
                  : const Text('Revisar'),
            )
          else ...[
            _PlanCard(
              rows: [
                ('Para', review.to),
                ('Enviar', formatEth(review.value)),
                ('Taxa máxima', formatEth(review.maxFee)),
              ],
              note: 'A taxa cobrada costuma ser bem menor que a máxima.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Criar arquivo para assinar'),
              onPressed: () => _saveRequest(context, _request!),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Solana --

class SolSendScreen extends StatefulWidget {
  const SolSendScreen({
    super.key,
    required this.services,
    required this.balance,
  });

  final OnlineServices services;
  final BigInt balance;

  @override
  State<SolSendScreen> createState() => _SolSendScreenState();
}

class _SolSendScreenState extends State<SolSendScreen> {
  final _destination = TextEditingController();
  final _amount = TextEditingController();
  bool _sendAll = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _destination.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await SolSend.buildRequest(
        network: widget.services.wallet.network,
        from: widget.services.wallet.solAddress,
        to: _destination.text,
        amount: _sendAll ? null : Amounts.parse(_amount.text, 9),
        client: widget.services.sol,
      );
      if (mounted) await _saveRequest(context, request);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar Solana')),
      body: PageFrame(
        children: [
          AvailableCard(formatSol(widget.balance), label: 'Saldo'),
          const SizedBox(height: 8),
          _SendFields(
            destination: _destination,
            amount: _amount,
            sendAll: _sendAll,
            onSendAll: (v) => setState(() => _sendAll = v),
            unit: 'SOL',
            enabled: !_busy,
          ),
          Notice(
            kind: NoticeKind.warning,
            text:
                'Taxa: ${formatSol(SolSend.baseFee)}. Atenção: o pedido expira '
                'em cerca de 1 minuto. Deixe o assinador frio já aberto antes '
                'de criar o arquivo.',
          ),
          _ErrorText(_error),
          FilledButton.icon(
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Criar arquivo para assinar'),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}
