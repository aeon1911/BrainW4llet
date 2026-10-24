import 'package:flutter/material.dart';

import '../../features/btc/btc_send.dart';
import '../../features/btc/btc_wallet_state.dart';
import '../../features/btc/esplora_client.dart';
import '../../features/evm/evm_send.dart';
import '../../features/sol/sol_send.dart';
import '../../features/transfer/transfer_document.dart';
import '../../features/wallet/amounts.dart';
import '../widgets/file_io.dart';
import '../widgets/format.dart';
import '../widgets/page_frame.dart';
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
          decoration: const InputDecoration(
            labelText: 'Endereço de destino',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          enabled: enabled && !sendAll,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Valor ($unit)',
            border: const OutlineInputBorder(),
          ),
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
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
}

// ---------------------------------------------------------------- Bitcoin --

class BtcSendScreen extends StatefulWidget {
  const BtcSendScreen({super.key, required this.services, required this.state});

  final OnlineServices services;
  final BtcWalletState state;

  @override
  State<BtcSendScreen> createState() => _BtcSendScreenState();
}

class _BtcSendScreenState extends State<BtcSendScreen> {
  final _destination = TextEditingController();
  final _amount = TextEditingController();
  final _customFee = TextEditingController();
  bool _sendAll = false;
  bool _busy = false;
  String? _error;
  BtcFeeRates? _rates;
  int? _feeRate;
  BtcSendPlan? _plan;

  @override
  void initState() {
    super.initState();
    widget.services.esplora
        .feeRates()
        .then((rates) {
          if (mounted) {
            setState(() {
              _rates = rates;
              _feeRate = rates.halfHour;
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
        account: widget.services.btcAccount,
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
        account: widget.services.btcAccount,
        rawTransaction: widget.services.esplora.rawTransaction,
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
      appBar: AppBar(title: const Text('Enviar Bitcoin')),
      body: PageFrame(
        children: [
          Text(
            'Saldo confirmado disponível: '
            '${formatBtc(widget.state.confirmedBalance)}',
          ),
          const SizedBox(height: 12),
          _SendFields(
            destination: _destination,
            amount: _amount,
            sendAll: _sendAll,
            onSendAll: (v) => setState(() {
              _sendAll = v;
              _plan = null;
            }),
            unit: 'BTC',
            enabled: !_busy,
          ),
          Text('Taxa', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          if (rates == null)
            const LinearProgressIndicator()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, rate) in [
                  ('Rápida', rates.fastest),
                  ('~30 min', rates.halfHour),
                  ('~1 hora', rates.hour),
                  ('Econômica', rates.economy),
                ])
                  ChoiceChip(
                    label: Text('$label · $rate sat/vB'),
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
              decoration: const InputDecoration(
                labelText: 'sat/vB',
                border: OutlineInputBorder(),
              ),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enviar: ${formatBtc(plan.amount)}'),
                    Text(
                      'Taxa: ${formatBtc(plan.fee)} (${plan.feeRate} sat/vB)',
                    ),
                    if (plan.change > BigInt.zero)
                      Text(
                        'Troco (volta para você): ${formatBtc(plan.change)}',
                      ),
                    Text('Moedas usadas: ${plan.inputs.length}'),
                    const Divider(),
                    Text(
                      'Total que sai: ${formatBtc(plan.amount + plan.fee)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
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
          Text('Saldo: ${formatEth(widget.balance)}'),
          const SizedBox(height: 12),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Para: ${review.to}'),
                    Text('Enviar: ${formatEth(review.value)}'),
                    Text('Taxa máxima: ${formatEth(review.maxFee)}'),
                    Text(
                      'A taxa cobrada costuma ser bem menor que a máxima.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
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
          Text('Saldo: ${formatSol(widget.balance)}'),
          const SizedBox(height: 12),
          _SendFields(
            destination: _destination,
            amount: _amount,
            sendAll: _sendAll,
            onSendAll: (v) => setState(() => _sendAll = v),
            unit: 'SOL',
            enabled: !_busy,
          ),
          Text(
            'Taxa: ${formatSol(SolSend.baseFee)}. Atenção: o pedido expira em '
            'cerca de 1 minuto. Deixe o assinador frio já aberto antes de '
            'criar o arquivo.',
            style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
          ),
          const SizedBox(height: 12),
          _ErrorText(_error),
          FilledButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text('Criar arquivo para assinar'),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}
