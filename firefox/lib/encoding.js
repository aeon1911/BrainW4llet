// Codificações usadas pelos endereços: hex, Base58(Check) e Bech32 (BIP-173).
// Tudo em Uint8Array; nada aqui toca em segredo.

import { sha256 } from './hash.js';

export function hexToBytes(hex) {
  if (!/^([0-9a-fA-F]{2})*$/.test(hex)) throw new Error('Hex inválido.');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

export function bytesToHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function concatBytes(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

export function bytesToBigInt(bytes) {
  return bytes.length ? BigInt('0x' + bytesToHex(bytes)) : 0n;
}

export function bigIntToBytes(value, length) {
  const hex = value.toString(16).padStart(length * 2, '0');
  if (hex.length > length * 2) throw new Error('Número grande demais.');
  return hexToBytes(hex);
}

const B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

export function base58Encode(bytes) {
  let n = bytesToBigInt(bytes);
  let out = '';
  while (n > 0n) {
    out = B58[Number(n % 58n)] + out;
    n /= 58n;
  }
  for (const b of bytes) {
    if (b !== 0) break;
    out = '1' + out;
  }
  return out;
}

export function base58Decode(text) {
  let n = 0n;
  for (const c of text) {
    const v = B58.indexOf(c);
    if (v < 0) throw new Error('Base58 inválido.');
    n = n * 58n + BigInt(v);
  }
  let hex = n === 0n ? '' : n.toString(16);
  if (hex.length % 2) hex = '0' + hex;
  const body = hexToBytes(hex);
  let zeros = 0;
  while (zeros < text.length && text[zeros] === '1') zeros++;
  return concatBytes(new Uint8Array(zeros), body);
}

async function checksum(payload) {
  return (await sha256(await sha256(payload))).slice(0, 4);
}

export async function base58CheckEncode(payload) {
  return base58Encode(concatBytes(payload, await checksum(payload)));
}

export async function base58CheckDecode(text) {
  const raw = base58Decode(text);
  if (raw.length < 5) throw new Error('Base58Check curto demais.');
  const payload = raw.slice(0, -4);
  const expected = await checksum(payload);
  if (!expected.every((b, i) => b === raw[raw.length - 4 + i])) {
    throw new Error('Soma de verificação inválida.');
  }
  return payload;
}

const BECH32 = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

function polymod(values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  let chk = 1;
  for (const v of values) {
    const top = chk >>> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (let i = 0; i < 5; i++) if ((top >>> i) & 1) chk ^= gen[i];
  }
  return chk;
}

function hrpExpand(hrp) {
  return [...[...hrp].map((c) => c.charCodeAt(0) >>> 5), 0, ...[...hrp].map((c) => c.charCodeAt(0) & 31)];
}

function convertBits(data, from, to) {
  let acc = 0;
  let bits = 0;
  const out = [];
  for (const v of data) {
    acc = (acc << from) | v;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.push((acc >>> bits) & ((1 << to) - 1));
    }
  }
  if (bits > 0) out.push((acc << (to - bits)) & ((1 << to) - 1));
  return out;
}

// Endereço SegWit v0 (bech32 clássico, BIP-173).
export function segwitV0Address(hrp, program) {
  const data = [0, ...convertBits(program, 8, 5)];
  const mod = polymod([...hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0]) ^ 1;
  const check = Array.from({ length: 6 }, (_, i) => (mod >>> (5 * (5 - i))) & 31);
  return hrp + '1' + [...data, ...check].map((v) => BECH32[v]).join('');
}
