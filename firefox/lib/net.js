// Cliente HTTP da extensão. Só fala com os servidores da lista abaixo (a
// mesma do app, sem o nó Monero) e limita tempo, tamanho e novas tentativas,
// para que um servidor ruim não trave nem encha a memória da extensão.

export const ENDPOINTS = {
  mainnet: {
    btcEsplora: 'https://mempool.space/api',
    btcExplorerTx: 'https://mempool.space/tx/',
    evmRpc: 'https://ethereum-rpc.publicnode.com',
    evmChainId: 1,
    evmBlockscout: 'https://eth.blockscout.com/api/v2',
    evmExplorerTx: 'https://etherscan.io/tx/',
    // O RPC oficial (api.mainnet-beta.solana.com) responde 403 a pedidos
    // de navegador; o publicnode aceita.
    solRpc: 'https://solana-rpc.publicnode.com',
    solExplorerTx: 'https://solscan.io/tx/',
    solExplorerSuffix: '',
    dashInsight: 'https://insight.dash.org/insight-api',
    dashExplorerTx: 'https://chainz.cryptoid.info/dash/tx.dws?',
    dashExplorerSuffix: '.htm',
    xmrExplorerTx: 'https://xmrchain.net/tx/',
  },
  testnet: {
    btcEsplora: 'https://mempool.space/testnet4/api',
    btcExplorerTx: 'https://mempool.space/testnet4/tx/',
    evmRpc: 'https://ethereum-sepolia-rpc.publicnode.com',
    evmChainId: 11155111,
    evmBlockscout: 'https://eth-sepolia.blockscout.com/api/v2',
    evmExplorerTx: 'https://sepolia.etherscan.io/tx/',
    solRpc: 'https://api.devnet.solana.com',
    solExplorerTx: 'https://solscan.io/tx/',
    solExplorerSuffix: '?cluster=devnet',
    xmrExplorerTx: 'https://stagenet.xmrchain.net/tx/',
  },
};

// Origens que a extensão pode consultar (iguais às host_permissions e ao
// connect-src do manifest).
export const ORIGINS = [
  'https://mempool.space',
  'https://ethereum-rpc.publicnode.com',
  'https://ethereum-sepolia-rpc.publicnode.com',
  'https://eth.blockscout.com',
  'https://eth-sepolia.blockscout.com',
  'https://solana-rpc.publicnode.com',
  'https://api.devnet.solana.com',
  'https://insight.dash.org',
];

const TIMEOUT_MS = 25_000;
const MAX_BYTES = 4 * 1024 * 1024;
const MAX_RETRIES = 4;
const MAX_RETRY_AFTER_MS = 30_000;

export class NetworkError extends Error {}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function readLimited(response) {
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BYTES) {
      await reader.cancel();
      throw new NetworkError('Resposta grande demais do servidor.');
    }
    chunks.push(value);
  }
  const all = new Uint8Array(size);
  let offset = 0;
  for (const c of chunks) {
    all.set(c, offset);
    offset += c.length;
  }
  return new TextDecoder().decode(all);
}

async function request(url, init = {}) {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || !ORIGINS.includes(parsed.origin)) {
    throw new NetworkError(`Servidor fora da lista permitida: ${parsed.host}`);
  }
  for (let attempt = 0; ; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    let response;
    let text;
    try {
      response = await fetch(url, {
        ...init,
        signal: controller.signal,
        credentials: 'omit',
        cache: 'no-store',
        referrerPolicy: 'no-referrer',
        redirect: 'error',
      });
      text = await readLimited(response);
    } catch (e) {
      if (e instanceof NetworkError) throw e;
      throw new NetworkError(`Falha ao acessar ${parsed.host}: ${e.name === 'AbortError' ? 'tempo esgotado' : e.message}`);
    } finally {
      clearTimeout(timer);
    }
    if (response.status === 429 && attempt < MAX_RETRIES) {
      const retryAfter = Number(response.headers.get('retry-after')) * 1000 || 0;
      await sleep(Math.min(Math.max(retryAfter, 1000 * 2 ** attempt), MAX_RETRY_AFTER_MS));
      continue;
    }
    if (response.status === 429) {
      throw new NetworkError(`${parsed.host} está limitando as consultas. Tente de novo em instantes.`);
    }
    if (!response.ok) {
      throw new NetworkError(`${parsed.host} respondeu ${response.status}.`);
    }
    return text;
  }
}

export async function getJson(url) {
  const text = await request(url);
  try {
    return JSON.parse(text);
  } catch {
    throw new NetworkError(`Resposta inválida de ${new URL(url).host}.`);
  }
}

let rpcId = 0;

export async function rpc(url, method, params = []) {
  const text = await request(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }),
  });
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  if (!json || typeof json !== 'object') throw new NetworkError(`Resposta inválida de ${method}.`);
  if (json.error != null) {
    throw new NetworkError(`${method}: ${typeof json.error === 'object' ? json.error.message : json.error}`);
  }
  return json.result;
}
