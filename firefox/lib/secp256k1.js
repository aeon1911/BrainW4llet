// Operações públicas da secp256k1 (somar pontos e multiplicar por escalar
// público). Sem chaves privadas: por isso não precisa ser de tempo constante.

import { bigIntToBytes, bytesToBigInt, concatBytes } from './encoding.js';

export const P = 2n ** 256n - 2n ** 32n - 977n;
export const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const G = {
  x: 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798n,
  y: 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8n,
};

const mod = (a, m = P) => ((a % m) + m) % m;

function pow(base, exp, m = P) {
  let result = 1n;
  base = mod(base, m);
  while (exp > 0n) {
    if (exp & 1n) result = (result * base) % m;
    base = (base * base) % m;
    exp >>= 1n;
  }
  return result;
}

function inv(a) {
  // Euclides estendido: bem mais rápido que a^(p-2) com BigInt.
  let [r0, r1] = [mod(a), P];
  let [s0, s1] = [1n, 0n];
  while (r1 !== 0n) {
    const q = r0 / r1;
    [r0, r1] = [r1, r0 - q * r1];
    [s0, s1] = [s1, s0 - q * s1];
  }
  if (r0 !== 1n) throw new Error('Sem inverso.');
  return mod(s0);
}

// Coordenadas jacobianas (X, Y, Z): um único inverso no final.
const INF = { x: 0n, y: 1n, z: 0n };

function jDouble(p) {
  if (p.z === 0n || p.y === 0n) return INF;
  const ysq = (p.y * p.y) % P;
  const s = (4n * p.x * ysq) % P;
  const m = (3n * p.x * p.x) % P;
  const x = mod(m * m - 2n * s);
  const y = mod(m * (s - x) - 8n * ysq * ysq);
  const z = (2n * p.y * p.z) % P;
  return { x, y, z };
}

function jAdd(p, q) {
  if (p.z === 0n) return q;
  if (q.z === 0n) return p;
  const z1z1 = (p.z * p.z) % P;
  const z2z2 = (q.z * q.z) % P;
  const u1 = (p.x * z2z2) % P;
  const u2 = (q.x * z1z1) % P;
  const s1 = (p.y * q.z * z2z2) % P;
  const s2 = (q.y * p.z * z1z1) % P;
  if (u1 === u2) return s1 === s2 ? jDouble(p) : INF;
  const h = mod(u2 - u1);
  const r = mod(s2 - s1);
  const h2 = (h * h) % P;
  const h3 = (h2 * h) % P;
  const u1h2 = (u1 * h2) % P;
  const x = mod(r * r - h3 - 2n * u1h2);
  const y = mod(r * (u1h2 - x) - s1 * h3);
  const z = (h * p.z * q.z) % P;
  return { x, y, z };
}

function toAffine(p) {
  if (p.z === 0n) return null;
  const zi = inv(p.z);
  const zi2 = (zi * zi) % P;
  return { x: (p.x * zi2) % P, y: (p.y * zi2 * zi) % P };
}

const fromAffine = (a) => ({ x: a.x, y: a.y, z: 1n });

function mul(k, point) {
  let result = INF;
  let addend = fromAffine(point);
  while (k > 0n) {
    if (k & 1n) result = jAdd(result, addend);
    addend = jDouble(addend);
    k >>= 1n;
  }
  return result;
}

// Ponto a partir da chave pública comprimida (33 bytes). Lança se não
// estiver na curva.
export function decompress(bytes) {
  if (bytes.length !== 33 || (bytes[0] !== 2 && bytes[0] !== 3)) {
    throw new Error('Chave pública inválida.');
  }
  const x = bytesToBigInt(bytes.slice(1));
  if (x >= P) throw new Error('Chave pública inválida.');
  const ySq = mod(x * x * x + 7n);
  let y = pow(ySq, (P + 1n) / 4n);
  if ((y * y) % P !== ySq) throw new Error('Chave pública fora da curva.');
  if ((y & 1n) !== BigInt(bytes[0] & 1)) y = P - y;
  return { x, y };
}

export function compress(point) {
  return concatBytes(Uint8Array.of(point.y & 1n ? 3 : 2), bigIntToBytes(point.x, 32));
}

// tweak·G + point (derivação BIP-32 pública).
export function tweakAdd(point, tweak) {
  if (tweak <= 0n || tweak >= N) throw new Error('Derivação inválida.');
  const result = toAffine(jAdd(mul(tweak, G), fromAffine(point)));
  if (!result) throw new Error('Derivação inválida.');
  return result;
}
