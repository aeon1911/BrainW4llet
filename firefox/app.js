// Interface da extensão: importar o arquivo somente leitura, ver saldo,
// histórico e endereço de recebimento. Todo o DOM é montado com
// createElement (nunca innerHTML): textos de servidores não viram HTML.

import { UtxoAccount } from './lib/bip32.js';
import { COINS, coinsOf, syncCoin } from './lib/chains.js';
import { formatAgo, formatDate, formatSigned, formatUnits } from './lib/format.js';
import { ENDPOINTS } from './lib/net.js';
import { qrSvg } from './lib/qr.js';
import {
  forgetWallet,
  hasNetworkPermission,
  loadCache,
  loadWallet,
  openInTab,
  requestNetworkPermission,
  saveCache,
  saveWallet,
} from './lib/store.js';
import { parseWatchOnly } from './lib/watchonly.js';

const isPopup = location.hash === '#popup';
const main = document.getElementById('main');

const state = {
  wallet: null,
  remembered: false,
  coin: 'btc',
  cache: {},
  loading: new Set(),
  errors: {},
  showQr: false,
  permission: true,
  confirmForget: false,
};

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value == null || value === false) continue;
    if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
    else if (key === 'class') el.className = value;
    else if (key === 'style') for (const [p, v] of Object.entries(value)) el.style.setProperty(p, v);
    else el.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) {
    if (child == null || child === false) continue;
    el.append(child instanceof Node ? child : String(child));
  }
  return el;
}

function render() {
  document.getElementById('network').hidden = state.wallet?.network !== 'testnet';
  main.replaceChildren(...(state.wallet ? walletView() : importView()).filter(Boolean));
}

// ---------------------------------------------------------------- importar

function importView() {
  const error = h('div', { class: 'error', role: 'alert', hidden: true });
  const remember = h('input', { type: 'checkbox', id: 'remember' });
  const input = h('input', { type: 'file', accept: '.json,application/json', hidden: true });
  input.addEventListener('change', async () => {
    const file = input.files[0];
    input.value = '';
    if (!file) return;
    try {
      if (file.size > 64 * 1024) throw new Error('Arquivo grande demais para ser uma carteira somente leitura.');
      const wallet = await parseWatchOnly(await file.text());
      await saveWallet(wallet, remember.checked);
      state.wallet = wallet;
      state.remembered = remember.checked;
      state.cache = {};
      state.coin = 'btc';
      render();
    } catch (e) {
      error.textContent = e.message;
      error.hidden = false;
    }
  });

  const choose = h('button', {
    class: 'primary',
    type: 'button',
    // No popup o seletor de arquivos fecha a janela: importa numa aba.
    onclick: () => (isPopup ? openInTab().then(() => window.close()) : input.click()),
  }, isPopup ? 'Importar numa aba…' : 'Escolher arquivo…');

  return [
    h('section', { class: 'card' },
      h('h2', {}, 'Importe a carteira somente leitura'),
      h('p', {}, 'No assinador (aparelho offline), destrave a carteira e use “Exportar carteira somente leitura”. Traga o arquivo .json até aqui.'),
      h('ul', { class: 'checks' },
        h('li', {}, 'O arquivo não tem nenhuma chave que gaste.'),
        h('li', {}, 'A view key do Monero é descartada ao importar.'),
        h('li', {}, 'Confira a impressão digital com a do assinador.')),
      isPopup ? null : h('label', { class: 'check', for: 'remember' }, remember,
        h('span', {}, 'Lembrar neste navegador',
          h('small', {}, 'Sem marcar, a carteira some quando o Firefox fecha.'))),
      input,
      h('div', { class: 'stack' }, choose, error)),
    footer(),
  ];
}

// --------------------------------------------------------------- carteira

function walletView() {
  const { wallet } = state;
  const coins = coinsOf(wallet);
  if (!coins.includes(state.coin)) state.coin = coins[0];

  const tabs = h('div', { class: 'tabs', role: 'tablist' }, coins.map((c) =>
    h('button', {
      type: 'button',
      role: 'tab',
      'aria-selected': String(c === state.coin),
      style: { '--coin': COINS[c].color },
      onclick: () => {
        state.coin = c;
        state.showQr = false;
        render();
        autoSync();
      },
    }, h('span', { class: 'dot' }), COINS[c].ticker)));

  return [
    h('div', { class: 'row spread' },
      h('span', { class: 'fingerprint' }, 'Impressão digital ', h('b', { class: 'mono' }, wallet.fingerprint)),
      h('span', { class: 'caption' }, state.remembered ? 'lembrada' : 'só nesta sessão')),
    state.permission ? null : permissionCard(),
    tabs,
    state.coin === 'xmr' ? moneroCard() : coinCard(state.coin),
    footer(),
  ];
}

function permissionCard() {
  return h('section', { class: 'notice' },
    h('p', { style: { margin: '0 0 8px' } }, 'A extensão precisa de permissão para consultar os servidores públicos (mempool.space, publicnode, Blockscout, Solana devnet e Insight).'),
    h('button', {
      class: 'primary small',
      type: 'button',
      onclick: () => requestNetworkPermission().then((ok) => {
        state.permission = ok;
        render();
        autoSync();
      }),
    }, 'Permitir acesso'));
}

function coinCard(coin) {
  const info = COINS[coin];
  const data = state.cache[coin];
  const loading = state.loading.has(coin);
  const error = state.errors[coin];

  const header = h('div', { class: 'row spread' },
    h('span', { class: 'section-title' }, info.name),
    h('div', { class: 'row' },
      loading ? h('span', { class: 'spinner', 'aria-label': 'Atualizando' }) : null,
      data ? h('span', { class: 'caption' }, formatAgo(data.at)) : null,
      h('button', { class: 'small', type: 'button', disabled: loading || !state.permission, onclick: () => sync(coin) }, 'Atualizar')));

  const balance = data
    ? [
        h('div', { class: 'balance' }, formatUnits(data.confirmed, info.decimals), ' ', h('small', {}, info.ticker)),
        BigInt(data.pending) !== 0n
          ? h('div', { class: 'pending' }, `${formatSigned(data.pending, info.decimals, info.ticker)} pendente`)
          : null,
      ]
    : h('div', { class: 'balance' }, '—');

  return h('section', { class: 'card stack', style: { '--coin': info.color } },
    header,
    balance,
    error ? h('div', { class: 'error', role: 'alert' }, error) : null,
    receiveSection(coin, data),
    historySection(coin, data));
}

function receiveSection(coin, data) {
  const holder = h('div', { class: 'stack' });
  const fill = (address, caption) => {
    holder.replaceChildren(...[
      h('span', { class: 'section-title' }, 'Receber'),
      addressBox(address),
      caption ? h('span', { class: 'caption' }, caption) : null,
      state.showQr ? h('div', { class: 'qr', 'aria-label': `QR do endereço ${address}` }, qrSvg(address)) : null,
      h('div', { class: 'notice' }, 'Antes de receber valores altos, confira este endereço no assinador (“Conferir endereço”).'),
    ].filter(Boolean));
  };
  const utxo = coin === 'btc' || coin === 'dash';
  if (data?.receive) {
    fill(data.receive.address, utxo ? `Endereço nº ${data.receive.index} — o próximo sem uso.` : null);
  } else if (!utxo) {
    fill(coin === 'eth' ? state.wallet.ethAddress : state.wallet.solAddress);
  } else {
    holder.append(h('span', { class: 'caption' }, 'Derivando endereço…'));
    const account = coin === 'btc'
      ? UtxoAccount.bitcoin(state.wallet.btcAccountKey, state.wallet.network)
      : UtxoAccount.dash(state.wallet.dashAccountKey);
    account.then((a) => a.address(0, 0)).then(
      (address) => fill(address, 'Primeiro endereço. Atualize para ver o próximo sem uso.'),
      (e) => holder.replaceChildren(h('div', { class: 'error' }, e.message)));
  }
  return holder;
}

function addressBox(address) {
  const copy = h('button', { class: 'icon-button', type: 'button', title: 'Copiar', 'aria-label': 'Copiar endereço' }, copyIcon());
  copy.addEventListener('click', async () => {
    await navigator.clipboard.writeText(address);
    copy.replaceChildren('✓');
    setTimeout(() => copy.replaceChildren(copyIcon()), 1500);
  });
  const qr = h('button', {
    class: 'icon-button',
    type: 'button',
    title: state.showQr ? 'Esconder QR' : 'Mostrar QR',
    'aria-pressed': String(state.showQr),
    onclick: () => {
      state.showQr = !state.showQr;
      render();
    },
  }, 'QR');
  return h('div', { class: 'address' }, h('span', { class: 'mono' }, address), copy, qr);
}

function copyIcon() {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', '18');
  svg.setAttribute('height', '18');
  const path = document.createElementNS(ns, 'path');
  path.setAttribute('fill', 'currentColor');
  path.setAttribute('d', 'M16 1H6a2 2 0 0 0-2 2v12h2V3h10V1zm3 4H10a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2zm0 16h-9V7h9v14z');
  svg.append(path);
  return svg;
}

function historySection(coin, data) {
  if (!data) return null;
  const info = COINS[coin];
  const rows = data.history.map((entry) => {
    const delta = entry.delta == null ? null : BigInt(entry.delta);
    return h('li', {},
      h('span', { class: `amount ${delta != null && delta > 0n ? 'in' : 'out'}` },
        delta == null ? '?' : formatSigned(delta, info.decimals, info.ticker),
        entry.pending ? h('span', { class: 'tag pending' }, 'pendente') : null,
        entry.failed ? h('span', { class: 'tag failed' }, 'falhou') : null),
      h('span', { class: 'meta' }, formatDate(entry.time)),
      h('a', { href: entry.url, target: '_blank', rel: 'noopener noreferrer', title: entry.id }, 'ver ↗'));
  });
  return h('div', { class: 'stack' },
    h('span', { class: 'section-title' }, 'Histórico'),
    rows.length ? h('ul', { class: 'history' }, rows) : h('span', { class: 'caption' }, 'Nenhuma transação ainda.'));
}

function moneroCard() {
  const address = state.wallet.xmrAddress;
  return h('section', { class: 'card stack', style: { '--coin': COINS.xmr.color } },
    h('span', { class: 'section-title' }, state.wallet.network === 'testnet' ? 'Monero (stagenet)' : 'Monero'),
    h('div', { class: 'notice info' }, 'O saldo do Monero exige varrer blocos com a view key, o que a extensão não faz (e ela não guarda a view key). Use o app BrainW4llet ou o Feather Wallet para ver o saldo.'),
    h('span', { class: 'section-title' }, 'Receber'),
    addressBox(address),
    state.showQr ? h('div', { class: 'qr', 'aria-label': 'QR do endereço Monero' }, qrSvg(address)) : null,
    h('div', { class: 'notice' }, 'Antes de receber valores altos, confira este endereço no assinador (“Conferir endereço”).'));
}

function footer() {
  const ep = state.wallet ? ENDPOINTS[state.wallet.network] : null;
  const servers = ep
    ? `Servidores: ${[ep.btcEsplora, ep.evmRpc, ep.evmBlockscout, ep.solRpc, ep.dashInsight]
        .filter(Boolean)
        .map((url) => new URL(url).host)
        .join(', ')}.`
    : null;
  return h('footer', { class: 'foot' },
    state.wallet ? h('span', {}, 'Para enviar, use o app BrainW4llet: a extensão não monta nem assina transações.') : null,
    servers ? h('span', {}, `${servers} Eles veem seus endereços e seu IP.`) : null,
    state.wallet
      ? h('div', { class: 'row' },
          h('button', {
            class: 'small danger',
            type: 'button',
            onclick: async () => {
              if (!state.confirmForget) {
                state.confirmForget = true;
                render();
                return;
              }
              await forgetWallet();
              Object.assign(state, { wallet: null, cache: {}, errors: {}, confirmForget: false });
              render();
            },
          }, state.confirmForget ? 'Confirmar: esquecer carteira' : 'Esquecer carteira'),
          state.confirmForget
            ? h('button', { class: 'small', type: 'button', onclick: () => { state.confirmForget = false; render(); } }, 'Cancelar')
            : null)
      : null);
}

// ---------------------------------------------------------- sincronização

async function sync(coin) {
  if (state.loading.has(coin) || coin === 'xmr') return;
  const fingerprint = state.wallet.fingerprint;
  state.loading.add(coin);
  delete state.errors[coin];
  render();
  try {
    const result = await syncCoin(coin, state.wallet);
    if (state.wallet?.fingerprint !== fingerprint) return;
    state.cache[coin] = { ...result, at: Date.now() };
    await saveCache(fingerprint, state.cache);
  } catch (e) {
    state.errors[coin] = e.message;
  } finally {
    state.loading.delete(coin);
    render();
  }
}

const STALE_MS = 5 * 60 * 1000;

function autoSync() {
  const coin = state.coin;
  const data = state.cache[coin];
  if (state.permission && coin !== 'xmr' && (!data || Date.now() - data.at > STALE_MS)) sync(coin);
}

async function start() {
  if (isPopup) {
    document.body.classList.add('popup');
    const openTab = document.getElementById('open-tab');
    openTab.hidden = false;
    openTab.addEventListener('click', () => openInTab().then(() => window.close()));
  }
  const saved = await loadWallet();
  if (saved) {
    state.wallet = saved.wallet;
    state.remembered = saved.remembered;
    state.cache = await loadCache(saved.wallet.fingerprint);
    state.permission = await hasNetworkPermission();
  }
  render();
  if (state.wallet) autoSync();
}

start();
