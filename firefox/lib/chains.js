// Saldo, histórico e próximo endereço de cada moeda. Mesma lógica da
// carteira online do app (BtcSync, EvmClient, SolClient, InsightClient).
// Valores em unidades base, como texto (BigInt não passa por storage).

import { UtxoAccount } from './bip32.js';
import { ENDPOINTS, NetworkError, getJson, rpc } from './net.js';

const GAP_LIMIT = 20;
const BATCH = 4;
const HISTORY_LIMIT = 25;

const big = (v) => (Number.isSafeInteger(v) ? BigInt(v) : 0n);

function object(v, coin) {
  if (v && typeof v === 'object' && !Array.isArray(v)) return v;
  throw new NetworkError(`Resposta inesperada do servidor ${coin}.`);
}

function list(v, coin) {
  if (Array.isArray(v)) return v;
  throw new NetworkError(`Resposta inesperada do servidor ${coin}.`);
}

// "0.00117200" (DASH em texto) → duffs, sem ponto flutuante.
export function decimalToUnits(value, decimals) {
  const text = typeof value === 'number' ? value.toFixed(decimals) : String(value ?? '0');
  if (!/^\d+(\.\d+)?$/.test(text)) return 0n;
  const [whole, fraction = ''] = text.split('.');
  return BigInt(whole + fraction.padEnd(decimals, '0').slice(0, decimals));
}

const esplora = (base) => ({
  coin: 'Bitcoin',
  async stats(address) {
    const json = object(await getJson(`${base}/address/${address}`), 'Bitcoin');
    const chain = object(json.chain_stats, 'Bitcoin');
    const mempool = object(json.mempool_stats, 'Bitcoin');
    const balance = (s) => big(s.funded_txo_sum) - big(s.spent_txo_sum);
    return {
      txCount: (chain.tx_count | 0) + (mempool.tx_count | 0),
      confirmed: balance(chain),
      pending: balance(mempool),
    };
  },
  async transactions(address) {
    return list(await getJson(`${base}/address/${address}/txs`), 'Bitcoin').map((t) => {
      const status = object(t.status, 'Bitcoin');
      return {
        txid: String(t.txid),
        confirmed: status.confirmed === true,
        time: Number.isSafeInteger(status.block_time) ? status.block_time * 1000 : null,
        inputs: list(t.vin, 'Bitcoin')
          .filter((vin) => vin && vin.prevout)
          .map((vin) => [vin.prevout.scriptpubkey_address ?? null, big(vin.prevout.value)]),
        outputs: list(t.vout, 'Bitcoin').map((vout) => [vout.scriptpubkey_address ?? null, big(vout.value)]),
      };
    });
  },
});

const insight = (base) => ({
  coin: 'Dash',
  async stats(address) {
    const json = object(await getJson(`${base}/addr/${address}?noTxList=1`), 'Dash');
    return {
      txCount: (json.txApperances | 0) + (json.unconfirmedTxApperances | 0),
      confirmed: big(json.balanceSat),
      pending: big(json.unconfirmedBalanceSat),
    };
  },
  async transactions(address) {
    const json = object(await getJson(`${base}/addrs/${address}/txs?from=0&to=50`), 'Dash');
    return list(json.items, 'Dash').map((t) => {
      const confirmed = (t.confirmations | 0) > 0;
      const time = t.blocktime ?? t.time;
      return {
        txid: String(t.txid),
        confirmed,
        time: confirmed && Number.isSafeInteger(time) ? time * 1000 : null,
        inputs: list(t.vin, 'Dash').map((vin) => [vin.addr ?? null, big(vin.valueSat)]),
        outputs: list(t.vout, 'Dash').map((vout) => [
          vout.scriptPubKey?.addresses?.[0] ?? null,
          decimalToUnits(vout.value, 8),
        ]),
      };
    });
  },
});

// Varre receber (0) e troco (1) até GAP_LIMIT endereços seguidos sem uso.
async function utxoSync(account, backend, explorerTx, explorerSuffix = '') {
  const mine = new Set();
  const used = [];
  let confirmed = 0n;
  let pending = 0n;
  let receive = null;
  for (const chain of [0, 1]) {
    let gap = 0;
    for (let index = 0; gap < GAP_LIMIT; index += BATCH) {
      const indexes = Array.from({ length: BATCH }, (_, i) => index + i);
      const addresses = [];
      for (const i of indexes) addresses.push(await account.address(chain, i));
      const stats = await Promise.all(addresses.map((a) => backend.stats(a)));
      stats.forEach((s, i) => {
        mine.add(addresses[i]);
        if (s.txCount > 0) {
          gap = 0;
          used.push(addresses[i]);
          confirmed += s.confirmed;
          pending += s.pending;
        } else {
          gap++;
          if (chain === 0 && receive === null) receive = { index: indexes[i], address: addresses[i] };
        }
      });
    }
  }

  const txs = new Map();
  for (let i = 0; i < used.length; i += BATCH) {
    const pages = await Promise.all(used.slice(i, i + BATCH).map((a) => backend.transactions(a)));
    for (const tx of pages.flat()) txs.set(tx.txid, tx);
  }
  const history = [...txs.values()].map((tx) => {
    const sum = (rows) => rows.reduce((n, [address, value]) => (mine.has(address) ? n + value : n), 0n);
    return {
      id: tx.txid,
      delta: (sum(tx.outputs) - sum(tx.inputs)).toString(),
      time: tx.time,
      pending: !tx.confirmed,
      failed: false,
      url: explorerTx + tx.txid + explorerSuffix,
    };
  });
  return {
    confirmed: confirmed.toString(),
    pending: pending.toString(),
    receive,
    history: sortHistory(history),
  };
}

function sortHistory(entries) {
  // Pendentes primeiro, depois do mais novo para o mais antigo.
  const time = (e) => e.time ?? Number.MAX_SAFE_INTEGER;
  return entries
    .sort((a, b) => time(b) - time(a))
    .slice(0, HISTORY_LIMIT);
}

function hexToBig(value, coin) {
  if (typeof value !== 'string' || !/^0x[0-9a-fA-F]*$/.test(value)) {
    throw new NetworkError(`Resposta inesperada do servidor ${coin}.`);
  }
  return value === '0x' ? 0n : BigInt(value);
}

async function evmSync(address, ep) {
  // Confere a rede do RPC: um servidor trocado não pode mostrar outro saldo.
  const chainId = hexToBig(await rpc(ep.evmRpc, 'eth_chainId'), 'Ethereum');
  if (chainId !== BigInt(ep.evmChainId)) throw new NetworkError('O servidor Ethereum está em outra rede.');
  const balance = hexToBig(await rpc(ep.evmRpc, 'eth_getBalance', [address, 'latest']), 'Ethereum');
  const json = await getJson(`${ep.evmBlockscout}/addresses/${address}/transactions`);
  const items = json && Array.isArray(json.items) ? json.items : [];
  const me = address.toLowerCase();
  const hashOf = (party) => (party && typeof party.hash === 'string' ? party.hash.toLowerCase() : null);
  const toBig = (v) => (/^\d+$/.test(String(v)) ? BigInt(String(v)) : 0n);
  const history = items
    .filter((item) => item && typeof item.hash === 'string')
    .map((item) => {
      const value = toBig(item.value);
      const fee = toBig(item.fee?.value);
      const failed = item.status === 'error';
      let delta = 0n;
      // Transação que falhou não move o valor, só cobra a taxa.
      if (hashOf(item.to) === me && !failed) delta += value;
      if (hashOf(item.from) === me) delta -= (failed ? 0n : value) + fee;
      const time = Date.parse(item.timestamp);
      return {
        id: item.hash,
        delta: delta.toString(),
        time: Number.isNaN(time) ? null : time,
        pending: item.timestamp == null,
        failed,
        url: ep.evmExplorerTx + item.hash,
      };
    });
  return { confirmed: balance.toString(), pending: '0', receive: { address }, history: sortHistory(history) };
}

async function solSync(address, ep) {
  const commitment = { commitment: 'confirmed' };
  const result = await rpc(ep.solRpc, 'getBalance', [address, commitment]);
  const lamports = big(result?.value);
  const sigs = await rpc(ep.solRpc, 'getSignaturesForAddress', [address, { limit: 10, ...commitment }]);
  const history = [];
  for (const s of Array.isArray(sigs) ? sigs : []) {
    if (!s || typeof s.signature !== 'string') continue;
    let delta = null;
    try {
      const tx = await rpc(ep.solRpc, 'getTransaction', [
        s.signature,
        { encoding: 'json', maxSupportedTransactionVersion: 0, ...commitment },
      ]);
      const index = tx?.transaction?.message?.accountKeys?.indexOf(address) ?? -1;
      if (index >= 0 && tx.meta) {
        delta = (big(tx.meta.postBalances?.[index]) - big(tx.meta.preBalances?.[index])).toString();
      }
    } catch (e) {
      if (!(e instanceof NetworkError)) throw e;
    }
    history.push({
      id: s.signature,
      delta,
      time: Number.isSafeInteger(s.blockTime) ? s.blockTime * 1000 : null,
      pending: false,
      failed: s.err != null,
      url: ep.solExplorerTx + s.signature + ep.solExplorerSuffix,
    });
  }
  return { confirmed: lamports.toString(), pending: '0', receive: { address }, history: sortHistory(history) };
}

export const COINS = {
  btc: { name: 'Bitcoin', ticker: 'BTC', decimals: 8, color: '#F7931A' },
  eth: { name: 'Ethereum', ticker: 'ETH', decimals: 18, color: '#7B8CF5' },
  sol: { name: 'Solana', ticker: 'SOL', decimals: 9, color: '#A06BFF' },
  dash: { name: 'Dash', ticker: 'DASH', decimals: 8, color: '#1C8CE6' },
  xmr: { name: 'Monero', ticker: 'XMR', decimals: 12, color: '#FF7A1A' },
};

export function coinsOf(wallet) {
  return ['btc', 'eth', 'sol', ...(wallet.dashAccountKey ? ['dash'] : []), ...(wallet.xmrAddress ? ['xmr'] : [])];
}

export async function syncCoin(coin, wallet) {
  const ep = ENDPOINTS[wallet.network];
  switch (coin) {
    case 'btc':
      return utxoSync(await UtxoAccount.bitcoin(wallet.btcAccountKey, wallet.network), esplora(ep.btcEsplora), ep.btcExplorerTx);
    case 'dash':
      return utxoSync(await UtxoAccount.dash(wallet.dashAccountKey), insight(ep.dashInsight), ep.dashExplorerTx, ep.dashExplorerSuffix);
    case 'eth':
      return evmSync(wallet.ethAddress, ep);
    case 'sol':
      return solSync(wallet.solAddress, ep);
    default:
      throw new Error(`Moeda sem sincronização: ${coin}`);
  }
}
