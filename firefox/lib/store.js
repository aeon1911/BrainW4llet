// Onde a carteira fica guardada. Por padrão só na sessão do navegador
// (storage.session: some ao fechar o Firefox). "Lembrar" grava em
// storage.local. Nada aqui permite gastar, mas a zpub revela todos os
// endereços e o histórico: é dado privado.

import { ORIGINS } from './net.js';

const ext = globalThis.browser ?? null;

// Fora da extensão (página de testes no navegador comum) usa o
// sessionStorage, só para desenvolvimento.
const devArea = {
  async get(key) {
    try {
      const raw = sessionStorage.getItem(key);
      return raw === null ? {} : { [key]: JSON.parse(raw) };
    } catch {
      return {};
    }
  },
  async set(items) {
    for (const [k, v] of Object.entries(items)) sessionStorage.setItem(k, JSON.stringify(v));
  },
  async remove(key) {
    sessionStorage.removeItem(key);
  },
};

const session = ext?.storage?.session ?? devArea;
const local = ext?.storage?.local ?? devArea;

const WALLET = 'wallet';
const CACHE = 'cache';

export async function loadWallet() {
  const fromSession = (await session.get(WALLET))[WALLET];
  if (fromSession) return { wallet: fromSession, remembered: false };
  const fromLocal = (await local.get(WALLET))[WALLET];
  return fromLocal ? { wallet: fromLocal, remembered: true } : null;
}

export async function saveWallet(wallet, remember) {
  await forgetWallet();
  await (remember ? local : session).set({ [WALLET]: wallet });
}

export async function forgetWallet() {
  await Promise.all([session.remove(WALLET), local.remove(WALLET), session.remove(CACHE)]);
}

// Último resultado de cada moeda, só na sessão (evita consultar os
// servidores toda vez que o popup abre).
export async function loadCache(fingerprint) {
  const cache = (await session.get(CACHE))[CACHE];
  return cache && cache.fingerprint === fingerprint ? cache.coins : {};
}

export async function saveCache(fingerprint, coins) {
  await session.set({ [CACHE]: { fingerprint, coins } });
}

const origins = ORIGINS.map((o) => `${o}/*`);

export async function hasNetworkPermission() {
  if (!ext?.permissions) return true;
  return ext.permissions.contains({ origins });
}

// Precisa ser chamado direto do clique (gesto do usuário).
export function requestNetworkPermission() {
  if (!ext?.permissions) return Promise.resolve(true);
  return ext.permissions.request({ origins });
}

export function openInTab() {
  const url = ext?.runtime ? ext.runtime.getURL('app.html') : 'app.html';
  if (ext?.tabs) return ext.tabs.create({ url });
  window.open(url, '_blank', 'noopener');
  return Promise.resolve();
}
