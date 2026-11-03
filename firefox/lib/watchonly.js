// Arquivo da carteira somente leitura gerado pelo assinador do app
// (WatchOnlyWallet em lib/features/wallet/watch_only.dart). Mesmo formato,
// mesmas validações e a mesma impressão digital.

import { UtxoAccount } from './bip32.js';
import { base58Decode, bytesToHex } from './encoding.js';
import { sha256 } from './hash.js';

export const FORMAT = 'brainw4llet-watch-only';
export const VERSION = 1;
const MAX_FILE_BYTES = 64 * 1024;

const ETH = /^0x[0-9a-fA-F]{40}$/;
const XMR = /^[1-9A-HJ-NP-Za-km-z]{95}$/;
const HEX64 = /^[0-9a-fA-F]{64}$/;

function fail(message) {
  throw new Error(message);
}

// Valida o JSON e devolve a carteira já sem a view key do Monero: ela entra
// na impressão digital e é descartada (a extensão não varre blocos).
export async function parseWatchOnly(text) {
  if (text.length > MAX_FILE_BYTES) fail('Arquivo grande demais para ser uma carteira somente leitura.');
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    fail('O arquivo não é um JSON válido.');
  }
  if (!json || typeof json !== 'object' || json.format !== FORMAT) {
    fail('Não é um arquivo de carteira BrainW4llet.');
  }
  if (json.version !== VERSION) fail('Versão do arquivo não suportada.');
  const network = json.network;
  if (network !== 'mainnet' && network !== 'testnet') fail('Rede desconhecida.');

  const required = (key) => {
    const value = json[key];
    if (typeof value !== 'string' || value === '') fail(`Campo "${key}" ausente no arquivo.`);
    return value;
  };
  const optional = (key) => (typeof json[key] === 'string' ? json[key] : null);

  const wallet = {
    network,
    btcAccountKey: required('btcAccountKey'),
    ethAddress: required('ethAddress'),
    solAddress: required('solAddress'),
    dashAccountKey: optional('dashAccountKey'),
    xmrAddress: optional('xmrAddress'),
    createdAt: optional('createdAt'),
  };
  const xmrViewKey = optional('xmrViewKey');

  try {
    await UtxoAccount.bitcoin(wallet.btcAccountKey, network);
  } catch (e) {
    fail(`Chave Bitcoin inválida: ${e.message}`);
  }
  if (!ETH.test(wallet.ethAddress)) fail('Endereço Ethereum inválido.');
  let sol;
  try {
    sol = base58Decode(wallet.solAddress);
  } catch {
    sol = null;
  }
  if (!sol || sol.length !== 32) fail('Endereço Solana inválido.');
  if (wallet.dashAccountKey !== null) {
    if (network !== 'mainnet') fail('Dash só existe na rede principal.');
    try {
      await UtxoAccount.dash(wallet.dashAccountKey);
    } catch (e) {
      fail(`Chave Dash inválida: ${e.message}`);
    }
  }
  if (wallet.xmrAddress !== null) {
    const prefix = network === 'mainnet' ? '4' : '5';
    if (!XMR.test(wallet.xmrAddress) || wallet.xmrAddress[0] !== prefix) {
      fail('Endereço Monero inválido para esta rede.');
    }
  }
  if (xmrViewKey !== null && !HEX64.test(xmrViewKey)) fail('View key do Monero inválida.');

  wallet.fingerprint = await fingerprint(wallet, xmrViewKey);
  return wallet;
}

// Igual a WatchOnlyWallet.fingerprint: SHA-256 de todos os campos e da rede,
// 4 primeiros bytes. Confira que é a mesma que o assinador mostra.
export async function fingerprint(wallet, xmrViewKey) {
  const text = [
    wallet.network,
    wallet.btcAccountKey,
    wallet.ethAddress,
    wallet.solAddress,
    wallet.dashAccountKey ?? '',
    wallet.xmrAddress ?? '',
    xmrViewKey ?? '',
  ].join('|');
  const hex = bytesToHex((await sha256(new TextEncoder().encode(text))).slice(0, 4)).toUpperCase();
  return `${hex.slice(0, 4)}-${hex.slice(4)}`;
}
