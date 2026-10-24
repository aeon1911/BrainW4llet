# core/security

Toda a criptografia sensível do BrainW4llet fica aqui. A UI (`lib/presentation`)
e a lógica de carteira (`lib/features/wallet`) só consomem esta API.
Arquitetura e decisões: `docs/AVALIACAO_SEGURANCA.md`.

| Arquivo | Responsabilidade |
|---|---|
| `input_normalizer.dart` | Normalização canônica v1 das respostas |
| `argon2id_params.dart` | Parâmetros de custo (v1 congelado) e piso de segurança |
| `life_keys_passphrase.dart` | Respostas → Argon2id (libsodium, em isolate) → `lifeKey` de 32 bytes |
| `bip39_seed.dart` | Mnemônica aleatória de 24 palavras (CSPRNG) e seed = BIP-39(mnemônica, hex(lifeKey)) |
| `session_guard.dart` | Cobre a tela em `inactive`; apaga tudo em `hidden/paused/detached` |
| `sodium_runtime.dart` | Instância única da libsodium (FFI, variante sumo) |
| `memory.dart` | `wipeBytes` para buffers no heap do Dart |

## Arquitetura de chaves (opção B)

```text
24 palavras aleatórias (CSPRNG, em metal) ─┐
                                           ├─► seed BIP-39 ─► chaves BIP-32/44
Chaves de Vida ─► Argon2id ─► lifeKey ─────┘   (passphrase = hex(lifeKey))
```

Quem acha o backup da seed não faz nada sem as respostas, e quem sabe as respostas
não faz nada sem a seed. A carteira é recuperável em qualquer carteira BIP-39 com
passphrase, desde que `hex(lifeKey)` seja reproduzido conforme a especificação abaixo.

## Esquema v1 — CONGELADO

Mudar **qualquer** item abaixo altera as chaves derivadas. Para evoluir, crie uma v2 com novos domínios.

- Normalização: NFKD → lowercase → NFKD → remove `\p{M}` → translitera
  `ß æ œ ø đ ð ł ı ħ ŧ þ` → remove `\p{Cf}` → espaços Unicode viram ` ` → remove `\p{Cc}`
  → colapsa espaços + trim → NFC.
- `password = "BrainW4llet/Passphrase/v1" 0x00 u32be(n) {u32be(len) utf8(resposta)}*`
- `salt = BLAKE2b-128("BrainW4llet/Salt/v1")` = `276c682c1440aabf4d002f3b2f71b9df`
- `lifeKey = Argon2id v1.3`, m = 524288 KiB (512 MiB), t = 4, p = 1, 32 bytes.
- `seed = PBKDF2-HMAC-SHA512(NFKD(mnemônica), "mnemonic" || hex_minúsculo(lifeKey), 2048)`
  (BIP-39 padrão).
- Endereços de conferência: ETH `m/44'/60'/0'/0/0`, BTC P2WPKH `m/84'/0'/0'/0/0`.

## Verificação

- Argon2id: vetores golden gerados com `openssl kdf ... ARGON2ID` (OpenSSL 3.6, validado
  antes contra a RFC 9106 §5.3), inclusive com os parâmetros de produção.
- PBKDF2/BIP-39: vetor oficial (`TREZOR`) e vetores calculados com `hashlib` (Python).
- Endereços: vetor público do BIP-84 e endereço Ethereum de referência de "abandon … about".
- libsodium: o código-fonte embutido no pacote `sodium` 4.1.2
  (`3rdparty/libsodium-1.0.22-stable.tar.gz`) tem assinatura minisign válida da chave
  da libsodium `RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3`. Reverifique
  a cada atualização do pacote.

## Regras

- Nunca use `print`/`debugPrint`/logs com respostas, seed, lifeKey ou chaves
  (`avoid_print` está como erro no analyzer). Mensagens de erro nunca incluem a entrada.
- Todo `SecureKey` recebe `dispose()` em `finally`.
- `String` do Dart não pode ser zerada: a UI limpa os campos assim que a derivação começa.
- A `blockchain_utils` mantém cópias das chaves no heap do Dart enquanto deriva
  (limitação conhecida). Caminho de endurecimento: libsecp256k1 via FFI.

## Próximos passos

- Assinatura air-gapped por QR (PSBT/BC-UR para BTC, EIP-4527 para EVM).
- Detectar gravação de tela (`UIScreen.isCaptured`) e ocultar o conteúdo.
- Calibrar o Argon2id no iPhone (o tempo aparece após derivar) antes de guardar fundos.
