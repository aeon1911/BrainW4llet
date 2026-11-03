// Testes da extensão. No navegador: test/test.html servido por HTTP local
// (`python3 -m http.server -d firefox`). No terminal: `node firefox/test/tests.js`
// (Node 22+). Não vão no .xpi.

import vectors from './vectors.js';
import { UtxoAccount, VERSIONS, p2pkhAddress, parseExtendedKey } from '../lib/bip32.js';
import { decimalToUnits } from '../lib/chains.js';
import { base58Decode, base58Encode, bytesToHex, hexToBytes } from '../lib/encoding.js';
import { formatSigned, formatUnits } from '../lib/format.js';
import { ripemd160 } from '../lib/hash.js';
import { getJson } from '../lib/net.js';
import { addEcc, formatBits, qrMatrix, rsDivisor, rsRemainder } from '../lib/qr.js';
import { fingerprint, parseWatchOnly } from '../lib/watchonly.js';

const results = [];

async function test(name, fn) {
  try {
    await fn();
    results.push({ name, ok: true });
  } catch (e) {
    results.push({ name, ok: false, error: e.message });
  }
}

function eq(actual, expected, label = '') {
  if (actual !== expected) throw new Error(`${label} esperado ${expected}, veio ${actual}`);
}

async function rejects(fn, pattern) {
  try {
    await fn();
  } catch (e) {
    if (pattern && !pattern.test(e.message)) throw new Error(`erro inesperado: ${e.message}`);
    return;
  }
  throw new Error('deveria ter falhado');
}

const validFile = (overrides = {}) => JSON.stringify({
  format: 'brainw4llet-watch-only',
  version: 1,
  network: 'mainnet',
  btcAccountKey: vectors.zpub,
  ethAddress: vectors.fingerprintInput[2],
  solAddress: vectors.fingerprintInput[3],
  ...overrides,
});

await test('RIPEMD-160 confere com o hashlib', () => {
  for (const [hex, digest] of Object.entries(vectors.ripemd)) eq(bytesToHex(ripemd160(hexToBytes(hex))), digest, hex.slice(0, 16));
});

await test('Base58 preserva zeros à esquerda', () => {
  const bytes = Uint8Array.of(0, 0, 1, 2, 255);
  eq(bytesToHex(base58Decode(base58Encode(bytes))), bytesToHex(bytes));
});

await test('BIP-84: endereços da zpub (rede principal)', async () => {
  const account = await UtxoAccount.bitcoin(vectors.zpub, 'mainnet');
  for (const [path, address] of Object.entries(vectors.zpubAddrs)) {
    const [chain, index] = path.split('/').map(Number);
    eq(await account.address(chain, index), address, path);
  }
});

await test('BIP-84: endereços da vpub (testnet)', async () => {
  const account = await UtxoAccount.bitcoin(vectors.vpub, 'testnet');
  for (const [path, address] of Object.entries(vectors.vpubAddrs)) {
    const [chain, index] = path.split('/').map(Number);
    eq(await account.address(chain, index), address, path);
  }
});

await test('Dash: endereços P2PKH da xpub', async () => {
  const account = await UtxoAccount.dash(vectors.dashXpub);
  for (const [path, address] of Object.entries(vectors.dashAddrs)) {
    const [chain, index] = path.split('/').map(Number);
    eq(await account.address(chain, index), address, path);
  }
});

await test('BIP-44: 1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA', async () => {
  const parsed = await parseExtendedKey(vectors.xpub44, VERSIONS.xpub);
  const account = new UtxoAccount(parsed, (pub) => p2pkhAddress(pub, 0));
  eq(await account.address(0, 0), vectors.xpub44Addr);
});

await test('zpub recusada como vpub (rede trocada)', () => rejects(() => UtxoAccount.bitcoin(vectors.zpub, 'testnet'), /inesperado/));

await test('chave com soma de verificação errada é recusada', () => {
  const broken = vectors.zpub.slice(0, -1) + (vectors.zpub.endsWith('s') ? 't' : 's');
  return rejects(() => UtxoAccount.bitcoin(broken, 'mainnet'));
});

await test('impressão digital igual à do app', async () => {
  const [network, btcAccountKey, ethAddress, solAddress] = vectors.fingerprintInput;
  eq(await fingerprint({ network, btcAccountKey, ethAddress, solAddress, dashAccountKey: null, xmrAddress: null }, null), vectors.fingerprint);
});

await test('arquivo válido é importado', async () => {
  const wallet = await parseWatchOnly(validFile({ xmrViewKey: 'ab'.repeat(32) }));
  eq(wallet.network, 'mainnet');
  eq('xmrViewKey' in wallet, false, 'view key descartada:');
});

await test('arquivos inválidos são recusados', async () => {
  await rejects(() => parseWatchOnly('{'), /JSON/);
  await rejects(() => parseWatchOnly(validFile({ format: 'outra-coisa' })), /BrainW4llet/);
  await rejects(() => parseWatchOnly(validFile({ version: 2 })), /Versão/);
  await rejects(() => parseWatchOnly(validFile({ network: 'testnet' })), /Bitcoin/);
  await rejects(() => parseWatchOnly(validFile({ ethAddress: '0x123' })), /Ethereum/);
  await rejects(() => parseWatchOnly(validFile({ solAddress: '111' })), /Solana/);
  await rejects(() => parseWatchOnly(validFile({ xmrAddress: '5'.repeat(95) })), /Monero/);
  await rejects(() => parseWatchOnly(validFile({ dashAccountKey: vectors.zpub })), /Dash/);
  await rejects(() => parseWatchOnly(' '.repeat(70 * 1024)), /grande/);
});

await test('Reed-Solomon: "HELLO WORLD" 1-M (vetor da norma)', () => {
  const data = [0x20, 0x5b, 0x0b, 0x78, 0xd1, 0x72, 0xdc, 0x4d, 0x43, 0x40, 0xec, 0x11, 0xec, 0x11, 0xec, 0x11];
  eq(bytesToHex(Uint8Array.from(rsRemainder(data, rsDivisor(10)))), 'c4232777ebd7e7e25d17');
  eq(addEcc(data, 1).length, 26);
});

await test('QR: bits de formato do nível M', () => {
  eq(formatBits(0), 0b101010000010010, 'máscara 0');
  eq(formatBits(4), 0b100010111111001, 'máscara 4');
});

await test('QR: tamanho e padrões de posição', () => {
  const xmr = qrMatrix('4'.repeat(95));
  eq(xmr.length, 41, 'Monero (versão 6):');
  const btc = qrMatrix(vectors.zpubAddrs['0/0']);
  eq(btc.length, 29, 'Bitcoin (versão 3):');
  for (const [x, y] of [[0, 0], [btc.length - 7, 0], [0, btc.length - 7]]) {
    eq(btc[y][x] && btc[y + 6][x + 6] && !btc[y + 1][x + 1] && btc[y + 3][x + 3], true, `localizador ${x},${y}`);
  }
});

await test('valores sem ponto flutuante', () => {
  eq(decimalToUnits('0.00117200', 8), 117200n);
  eq(decimalToUnits('12', 8), 1200000000n);
  eq(formatUnits('150000000', 8), '1.5');
  eq(formatUnits('1', 18), '0.000000000000000001');
  eq(formatSigned('-2500', 8, 'BTC'), '−0.000025 BTC');
});

await test('rede: só servidores da lista', () => rejects(() => getJson('https://evil.example/api'), /fora da lista/));

const failed = results.filter((r) => !r.ok).length;
const summary = failed ? `${failed} de ${results.length} falharam` : `${results.length} testes passaram`;
if (typeof document !== 'undefined') {
  const list = document.getElementById('results');
  for (const r of results) {
    const li = document.createElement('li');
    li.className = r.ok ? 'ok' : 'fail';
    li.textContent = r.ok ? `✓ ${r.name}` : `✗ ${r.name}: ${r.error}`;
    list.append(li);
  }
  document.getElementById('summary').textContent = summary;
  document.body.dataset.done = failed ? 'fail' : 'ok';
} else {
  // CI: `node firefox/test/tests.js`
  for (const r of results) console.log(r.ok ? `✓ ${r.name}` : `✗ ${r.name}: ${r.error}`);
  console.log(summary);
  if (failed) process.exitCode = 1;
}
