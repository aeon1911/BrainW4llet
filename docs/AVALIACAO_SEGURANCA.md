# Avaliação de Segurança — BrainW4llet (cold wallet pessoal, iPhone)

Data: 2026-10-23 · Decisões na §8 · Escopo: arquitetura de chaves, stack criptográfica, plataforma iOS
e distribuição via AltStore. Usuário único; objetivo declarado: **segurança extrema**.

---

## 1. Veredito

| Item | Situação | Gravidade |
|---|---|---|
| Chaves derivadas **só** de respostas pessoais (brainwallet) | Incompatível com "segurança extrema" | **Crítica** |
| iPhone como dispositivo frio + AltStore (cert. de 7 dias) | Exige ficar online periodicamente | Alta |
| Argon2id em Dart puro (64 MiB) | Correto, mas lento → limita o custo possível | Média |
| `bip39` / `bip32` (abandonados) + `web3dart` (rede) | Conflito de dependências e superfície desnecessária | Média |
| Zeroização de memória em Dart | Só parcial (GC, `String` imutável) | Média |
| Normalização + Argon2id + vetores de teste | Implementado e validado bit a bit contra OpenSSL/RFC 9106 | OK |

A recomendação principal (§3) é manter as "Chaves de Vida", mas como **segundo fator**
(passphrase BIP-39), não como única fonte da chave.

---

## 2. Modelo de ameaça

**Atacantes considerados:**

1. **Remoto e em massa:** varre brainwallets com dicionários. Ataca *todos* os endereços
   que existem e não precisa saber quem você é.
2. **Direcionado:** sabe quem você é (redes sociais, vazamentos de dados brasileiros, conhecidos)
   e testa respostas plausíveis para *você*.
3. **Com acesso físico ao iPhone:** furto, perícia, coerção.
4. **Cadeia de suprimentos:** pacote Dart malicioso/comprometido, binário adulterado no build.
5. **Canal lateral no dispositivo:** teclado, área de transferência, snapshots, gravação de tela.

**Fora de escopo:** iOS comprometido por exploit de dia zero de nível estatal (mitigado
apenas por manter o aparelho permanentemente offline).

---

## 3. O problema central: entropia das "Chaves de Vida"

O Argon2id **multiplica o custo de cada tentativa por uma constante**; ele não cria
entropia. Se o espaço de respostas possíveis é pequeno, o ataque continua viável.

### Estimativa de entropia (ordem de grandeza)

| Resposta típica | Atacante em massa | Atacante direcionado |
|---|---|---|
| Nome do primeiro pet | ~10–14 bits | ~0–5 bits (Instagram) |
| Cidade natal | ~8–12 bits | ~0 bits (vazamentos/CPF) |
| Nome de solteira da mãe | ~12–16 bits | ~0–3 bits (cartório/vazamentos) |
| Primeira escola | ~10–14 bits | ~3–8 bits |
| **5 respostas somadas** | **~45–65 bits** | **~5–25 bits** |

Para comparação: **24 palavras BIP-39 aleatórias = 256 bits**. Uma resposta *inventada*
e aleatória (ex.: 6 palavras Diceware ≈ 77 bits) deixa de ser "resposta de vida".

### Custo de ataque com os parâmetros v1 (64 MiB, t=4)

O Argon2id é limitado pela banda de memória: cada tentativa movimenta ~0,5 GiB. Uma GPU
moderna (~1 TB/s) faz algo na ordem de **10³ tentativas/s**.

| Entropia | Tentativas | Custo aproximado |
|---|---|---|
| 20 bits | 10⁶ | minutos numa GPU |
| 40 bits | 10¹² | ~30 GPU-anos → dezenas de milhares de US$ em nuvem |
| 50 bits | 10¹⁵ | ~30 mil GPU-anos |
| 256 bits (seed aleatória) | 10⁷⁷ | inviável fisicamente |

O `identifier` (salt por usuário) impede a pré-computação em massa (atacante 1), mas
**não ajuda contra o atacante direcionado** (2), que é justamente quem sabe as suas respostas.
Brainwallets são esvaziadas rotineiramente na prática; isso é histórico, não teoria.

### Opções de arquitetura

| | A — Atual | **B — Recomendada** | C — Hardware wallet |
|---|---|---|---|
| Fonte da chave | Só respostas | Seed aleatória 256 bits (CSPRNG) **+** respostas como passphrase BIP-39 | Seed gerada em secure element |
| Atacante direcionado que sabe as respostas | **Rouba tudo** | Precisa também do backup físico da seed | Precisa do aparelho + PIN |
| Quem encontra o backup da seed | — | **Não rouba nada** (falta a passphrase) | Rouba (sem passphrase) |
| Precisa guardar algo físico | Não | Sim: 24 palavras em metal, escondidas | Sim |
| Zero persistência no iPhone | Sim | **Sim** (seed digitada/escaneada só na hora de assinar) | n/a |
| Compatível com outras carteiras | Só com este app | Sim: seed + passphrase em qualquer carteira BIP-39* | Sim |

\* A passphrase é `hex(Argon2id(respostas))`. Reproduzi-la fora do app exige o esquema
documentado em `lib/core/security/README.md`, que já está especificado e com vetores de teste.

A opção B preserva a ideia original (você precisa lembrar das respostas e o app não guarda
nada) e elimina o risco crítico. O custo é guardar um backup físico.

---

## 4. iPhone como cold wallet

**Riscos e mitigações:**

| Risco | Mitigação |
|---|---|
| Aparelho conectado à internet | iPhone **dedicado**, sem chip, Wi-Fi/Bluetooth desligados, sem conta iCloud. App **sem nenhum código de rede**; comunicação somente por **QR code** |
| AltStore com Apple ID gratuito: certificado expira em **7 dias** e renovar exige conexão com o AltServer | Conta Apple Developer paga (US$ 99/ano) → certificado de 1 ano. Ou aceitar janelas curtas e controladas online (o app vencido não abre, mas os fundos não se perdem: a chave é sempre rederivável) |
| AltServer oficial roda só em **macOS/Windows** | No Linux: AltServer-Linux (não oficial) ou SideStore. Ambos são terceiros e merecem a mesma desconfiança que qualquer dependência |
| Teclado aprende/sugere o que você digita | Campos com `obscureText`, `autocorrect: false`, `enableSuggestions: false`, `enableIMEPersonalizedLearning: false`. O iOS força o teclado do sistema em campos seguros |
| Área de transferência (sincroniza com o Mac via Universal Clipboard) | Nunca copiar seed, respostas ou chaves. Sem botão "copiar" para segredos |
| Snapshot no seletor de apps e screenshots | Cobrir a tela em `AppLifecycleState.inactive`; detectar gravação (`UIScreen.isCaptured`) e ocultar conteúdo |
| Memória após uso | Limpar tudo em `inactive/paused/detached` (já previsto no PROMPT_MESTRE) e usar memória protegida nativa (§5) |
| Jailbreak / dispositivo comprometido | Detecção é contornável; a defesa real é manter o aparelho offline |

### Fluxo de assinatura air-gapped recomendado

```text
[Dispositivo online, watch-only]               [iPhone frio, BrainW4llet]
 Sparrow (BTC) / Rabby ou MetaMask (EVM)
   monta transação não assinada  ── QR ──▶  mostra destino e valor, você confere
                                           deriva a chave (respostas + seed), assina
   transmite para a rede        ◀── QR ──  devolve a transação assinada e apaga tudo
```

Padrões: **PSBT (BIP-174) + BC-UR** para Bitcoin, **EIP-4527** (o protocolo de QR do Keystone)
para EVM. Implementar o mesmo protocolo do Keystone torna o app compatível com carteiras
watch-only existentes, sem escrever código de rede.

---

## 5. Stack criptográfica

### Argon2id

| Opção | Prós | Contras |
|---|---|---|
| `cryptography` 2.9 (atual, Dart puro) | Já validado contra a RFC 9106 e o OpenSSL; suporta p≥2 | Lento, o que impede subir a memória; buffers sujeitos ao GC |
| **`sodium` 4.1 + `sodium_libs` 4.0 (libsodium nativa)** | Auditada e onipresente; `crypto_pwhash` (Argon2id) rápido; **`SecureKey` em memória `sodium_malloc` (mlock + mprotect + zeroização)** | `crypto_pwhash` só suporta **p=1** (contraria o piso p≥2 do PROMPT_MESTRE); binário nativo |
| Argon2 de referência (PHC, C) via Dart native assets | Rápido; p≥2; mesmos vetores do OpenSSL | Compilação cruzada própria para 5 plataformas; sem memória protegida |

**Recomendação:** libsodium. Com código nativo dá para subir para **512 MiB–1 GiB**
(calibrado no iPhone, alvo de ~2–3 s), um ganho de 8–16× no custo do atacante. Isso vale
muito mais do que p=2. O paralelismo ajuda o *defensor* a gastar mais memória no mesmo
tempo; ele não encarece o ataque por si só. Exige aprovar a mudança do piso para p=1 e
criar o esquema **v2** (nada foi usado ainda, então não há migração).

### BIP-39 / BIP-32 / BIP-44 e redes

| Opção | Situação |
|---|---|
| `bip39` 1.0.6 + `bip32` 2.0.0 | Sem manutenção desde 2021; `pointycastle ^3` conflita com `web3dart` |
| `web3dart` 3.0.3 | Voltado a RPC/rede, desnecessário (e indesejável) num assinador frio |
| **`blockchain_utils` 7.1** (+ `bitcoin_base`, `on_chain`) | Dart puro, **zero dependências**, mantido (jul/2026); BIP-39/32/44, secp256k1, ed25519 (Solana), endereços BTC/EVM/SOL e PSBT |
| libsecp256k1 (Bitcoin Core) via FFI | Padrão-ouro: tempo constante e auditada; só faz secp256k1 |

**Recomendação:** `blockchain_utils` como base, com versões **fixadas exatamente** e
validação contra os vetores oficiais de BIP-39/32/44. Ressalva honesta: tem um mantenedor
principal e não conheço auditoria formal. A secp256k1 em Dart puro não é de tempo constante;
num aparelho offline, o risco de canal lateral é baixo, mas a libsecp256k1 via FFI fica
registrada como endurecimento futuro.

**Remover:** `web3dart`, `flutter_secure_storage` (uma cold wallet não tem o que guardar)
e qualquer pacote HTTP.

### Memória

A `String` do Dart é imutável e o GC pode copiar buffers; zeroizar só em Dart nunca é
garantido. Mitigações em camadas: (1) segredos em `SecureKey` da libsodium (fora do heap
do Dart, com mlock); (2) converter a entrada para bytes o quanto antes e limpar os
`TextEditingController`; (3) sessão curta, encerrada no `inactive`; (4) aparelho offline.

---

## 6. Cadeia de suprimentos e build

- `pubspec.lock` versionado, versões exatas (sem `^`) nos pacotes criptográficos e `flutter pub deps` revisado a cada mudança.
- Mínimo de dependências: o objetivo é `sodium(_libs)` + `blockchain_utils` (+ `bitcoin_base`/`on_chain`) + um leitor/gerador de QR.
- Testes com vetores oficiais (RFC 9106, BIP-39, BIP-32, BIP-44, EIP-155) como porteiro de qualquer atualização.
- **Build do IPA em máquina própria**, não em CI de terceiros, para a versão que vai guardar dinheiro de verdade. Um binário adulterado poderia exfiltrar a chave na primeira vez em que o aparelho ficar online.
- Baixar o AltStore/SideStore só das fontes oficiais.

---

## 7. Geração do IPA

O IPA de iOS **só pode ser compilado no macOS com Xcode**. O Flutter não faz compilação
cruzada de iOS a partir do Linux. Caminhos possíveis:

| Caminho | Segurança | Custo |
|---|---|---|
| **Mac próprio ou emprestado** (recomendado) | Melhor: build sob seu controle | Hardware |
| CI macOS (Codemagic, GitHub Actions) | Aceitável para *testes*; evitar na versão final (§6) | Plano gratuito com minutos limitados |
| macOS em VM num PC comum | A licença da Apple só permite VM em hardware Apple | Não recomendado |

No Mac, sem assinatura (o AltStore assina com o seu Apple ID):

```bash
flutter build ios --release --no-codesign
mkdir -p build/ipa/Payload && cp -R build/ios/iphoneos/Runner.app build/ipa/Payload/
(cd build/ipa && zip -qr ../BrainW4llet.ipa Payload)
```

---

## 8. Decisões (2026-10-23)

1. Arquitetura de chaves: **B**, seed aleatória de 24 palavras + Chaves de Vida → Argon2id → passphrase BIP-39.
   O `identifier` (salt por usuário) saiu: com a seed aleatória, não há pré-computação possível.
2. Argon2id: **libsodium** (`sodium` 4.1.2, sem `sodium_libs`, que foi descontinuado), p=1,
   **512 MiB, t=4**. Isso substitui o piso "parallelism ≥ 2" do PROMPT_MESTRE. A memória
   ficou 8× acima do mínimo.
3. Bibliotecas: `blockchain_utils` 7.1.0 no lugar de `bip39`/`bip32`/`web3dart`; sem
   `flutter_secure_storage` e sem pacotes de rede. Sem Riverpod/Bloc por enquanto (estado
   local simples; menos dependências).
4. IPA de teste: **Codemagic** (`codemagic.yaml` + `tool/build_ipa.sh`). Versão final: build local num Mac.
5. ~~Apple ID gratuito ou conta paga~~: o sideload com Apple ID gratuito parou de funcionar em
   set/2026. Por ora o app roda como AppImage (Linux).

### 2026-10-24: carteira funcional no modelo Electrum

6. O app tem dois papéis separados:
   - **Assinador frio** (`lib/presentation/unlock_screen.dart`, `cold/`): seed + Chaves de Vida,
     exporta a carteira somente leitura e assina. **Não instancia nenhum cliente de rede.**
   - **Carteira online** (`lib/presentation/online/`): abre o arquivo somente leitura (zpub/vpub,
     endereços ETH/SOL), mostra saldos e histórico, monta transações não assinadas e transmite as
     assinadas. **Não tem nenhuma chave privada.**
   - Entre os dois, arquivos JSON (`lib/features/transfer/transfer_document.dart`): PSBT (BTC),
     EIP-1559 não assinada (ETH) e mensagem legacy (SOL).
7. O assinador nunca confia nos metadados: destino, valores, troco e taxa são recalculados a partir
   da própria transação, e ele confere que cada entrada/remetente pertence à seed. Por enquanto,
   ETH e SOL só assinam transferências nativas simples (sem contratos ou tokens).
8. Servidores públicos (configuráveis no código, `lib/features/network/endpoints.dart`):
   mempool.space, publicnode.com + Blockscout e o RPC oficial da Solana. Existe uma rede de **teste**
   (testnet4, Sepolia, devnet) para exercitar o fluxo sem dinheiro real.
9. Assinaturas validadas por implementações independentes em Python (BIP-143 + ECDSA, ecrecover,
   Ed25519), e esses valores viraram testes permanentes.
10. Pendências: primeiro envio real de XMR na stagenet, tokens ERC-20/SPL, transferência por QR e durable nonce
    na Solana (hoje o pedido expira em ~1 minuto).
