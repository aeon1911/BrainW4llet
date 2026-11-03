// Chaves públicas estendidas (zpub/vpub/xpub) e derivação BIP-32 pública:
// só gera endereços, nunca chaves privadas.

import { hash160, hmacSha512 } from './hash.js';
import { base58CheckDecode, base58CheckEncode, bytesToBigInt, concatBytes, segwitV0Address } from './encoding.js';
import { compress, decompress, tweakAdd } from './secp256k1.js';

// Prefixos de versão (4 bytes) das chaves públicas estendidas.
export const VERSIONS = {
  zpub: 0x04b24746, // BIP-84, Bitcoin rede principal
  vpub: 0x045f1cf6, // BIP-84, Bitcoin testnet
  xpub: 0x0488b21e, // BIP-44 (Dash)
};

export async function parseExtendedKey(text, expectedVersion) {
  const raw = await base58CheckDecode(text.trim());
  if (raw.length !== 78) throw new Error('Chave estendida com tamanho errado.');
  const view = new DataView(raw.buffer, raw.byteOffset);
  if (view.getUint32(0) !== expectedVersion) {
    throw new Error('Tipo de chave estendida inesperado para esta moeda/rede.');
  }
  const key = raw.slice(45, 78);
  return { depth: raw[4], chainCode: raw.slice(13, 45), key, point: decompress(key) };
}

export async function derivePublicChild(parent, index) {
  if (!Number.isInteger(index) || index < 0 || index >= 0x80000000) {
    throw new Error('Só há derivação pública de índices não endurecidos.');
  }
  const data = new Uint8Array(37);
  data.set(parent.key);
  new DataView(data.buffer).setUint32(33, index);
  const i = await hmacSha512(parent.chainCode, data);
  const point = tweakAdd(parent.point, bytesToBigInt(i.slice(0, 32)));
  return { chainCode: i.slice(32), key: compress(point), point };
}

export async function p2wpkhAddress(publicKey, hrp) {
  return segwitV0Address(hrp, await hash160(publicKey));
}

export async function p2pkhAddress(publicKey, versionByte) {
  return base58CheckEncode(concatBytes(Uint8Array.of(versionByte), await hash160(publicKey)));
}

// Conta UTXO (BIP-84 ou BIP-44) a partir da chave pública da conta:
// cadeia 0 = receber, 1 = troco. Guarda as cadeias para não refazer o HMAC.
export class UtxoAccount {
  constructor(account, addressOf) {
    this.account = account;
    this.addressOf = addressOf;
    this.chains = new Map();
    this.cache = new Map();
  }

  static async bitcoin(key, network) {
    const testnet = network === 'testnet';
    const account = await parseExtendedKey(key, testnet ? VERSIONS.vpub : VERSIONS.zpub);
    return new UtxoAccount(account, (pub) => p2wpkhAddress(pub, testnet ? 'tb' : 'bc'));
  }

  static async dash(key) {
    const account = await parseExtendedKey(key, VERSIONS.xpub);
    return new UtxoAccount(account, (pub) => p2pkhAddress(pub, 0x4c));
  }

  async address(chain, index) {
    const id = `${chain}/${index}`;
    if (!this.cache.has(id)) {
      if (!this.chains.has(chain)) {
        this.chains.set(chain, await derivePublicChild(this.account, chain));
      }
      const child = await derivePublicChild(this.chains.get(chain), index);
      this.cache.set(id, await this.addressOf(child.key));
    }
    return this.cache.get(id);
  }
}
