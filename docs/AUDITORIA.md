# Auditoria de Segurança — BrainW4llet

**Data:** 2026-10-24 · **Versão auditada:** 0.1.0 · **Escopo:** todo o código em `lib/`, o formato dos
arquivos de transferência, as dependências diretas e o processo de build.

> **Limitação importante:** esta auditoria foi feita pelo mesmo assistente de IA que escreveu o
> código. Ela **não é independente**. Antes de guardar valores relevantes, vale uma revisão
> por outra pessoa ou empresa especializada, de preferência com acesso a este relatório.

---

## 1. Método

1. **Pontos de entrada:** tudo o que recebe dados de fora (arquivos de transferência, arquivo
   somente leitura, respostas de servidores, campos de texto) e tudo o que sai (rede, disco,
   área de transferência, logs).
2. **Busca por backdoors:** procura em todo o código próprio e nas dependências por sockets,
   clientes HTTP, execução de processos, URLs embutidas, telemetria e caminhos de dados
   sensíveis.
3. **Modelo de ameaça:** a carteira **online pode estar comprometida**. O assinador frio precisa
   impedir o roubo mesmo que tudo o que chega a ele (PSBT, transação ETH, mensagem SOL,
   metadados) tenha sido forjado por um atacante.
4. **Testes de ataque:** cada falha encontrada virou primeiro um teste que reproduz o ataque. A
   correção só foi aceita quando o mesmo teste passou a recusar o ataque.
5. **Verificação independente das assinaturas:** BIP-143 + ECDSA (BTC), ecrecover (ETH) e
   Ed25519 (SOL), implementados do zero em Python e comparados com o código Dart.

## 2. Superfície encontrada

| Item | Resultado |
|---|---|
| Acesso à rede | Um único cliente (`lib/features/network/http_json.dart`, `dart:io HttpClient`), instanciado **somente** por `OnlineServices` (telas da carteira online). O assinador frio nunca o cria. |
| Escrita em disco | Só quando o usuário escolhe onde salvar (`file_selector`): arquivo somente leitura, pedido de assinatura e transação assinada. **Nunca** seed, respostas ou chaves privadas. |
| Logs | Nenhum `print`/`debugPrint`/`log` no código (`avoid_print` configurado como erro). |
| Área de transferência | Só dados públicos, e a view key do Monero depois de revelada explicitamente. |
| Execução de processos / FFI direto | Nenhum no código próprio (a libsodium entra pelo pacote `sodium`). |
| Dependências criptográficas | `blockchain_utils`, `bitcoin_base`, `on_chain`: **nenhum** socket, cliente HTTP ou processo. As URLs embutidas são documentação e configurações de provedores que o app não instancia. `sodium`: só executa processos **na compilação**, para compilar a libsodium a partir do código-fonte embutido, cuja assinatura minisign foi conferida contra a chave oficial. |
| Telemetria / backdoor | **Nada encontrado**, nem no código próprio nem nas dependências. |

## 3. Achados e correções

| # | Gravidade | Achado | Status |
|---|---|---|---|
| C1 | **Crítica** | **BTC: o assinador herdava o tipo de assinatura (SIGHASH) do PSBT.** Uma carteira online comprometida podia pedir `SIGHASH_NONE`, `SINGLE` ou `ANYONECANPAY`. Com isso a assinatura não protegeria as saídas, e quem transmite trocaria o destino depois de assinado, roubando todas as entradas. Confirmado por teste antes da correção. | **Corrigido.** O assinador força `SIGHASH_ALL`, recusa qualquer outro tipo declarado e confere, depois de assinar, que cada assinatura final é `ALL` e vem da sua chave. Teste: `test/features/btc/btc_attack_test.dart`. |
| H1 | Alta | **Troca do endereço de recebimento.** Uma máquina online comprometida, ou um arquivo somente leitura adulterado, poderia mostrar o endereço de outra pessoa para você receber. | **Mitigado.** O assinador ganhou "Conferir endereço", que verifica contra a seed (ETH, SOL, XMR e 500 endereços de recebimento e de troco do BTC). A carteira online lembra de conferir antes de valores altos. |
| H2 | Alta | **Taxa abusiva sem alerta.** Um PSBT ou uma transação ETH forjada podia gastar o saldo como taxa; a revisão mostrava o valor, mas sem destaque. | **Corrigido.** Alertas para taxa BTC acima de 300 sat/vB ou acima de 10% do valor enviado, e para gás, preço de gás ou gorjeta anormais no ETH. Com algum alerta, é obrigatório marcar "Entendi" antes de assinar. |
| M1 | Média | Arquivo malformado podia derrubar o assinador (erros que não eram `Exception`, índice fora dos limites na mensagem Solana). | **Corrigido.** Checagem de limites no parser Solana e captura de qualquer erro ao abrir arquivos. |
| M2 | Média | Saídas BTC não padrão (ex.: OP_RETURN) não eram tratadas na revisão. | **Corrigido.** São recusadas com mensagem clara. |
| M3 | Média | ETH: lista de acesso (access list) era aceita sem necessidade. | **Corrigido.** Recusada. |
| M4 | Média | A impressão digital da carteira não cobria Dash e Monero; um arquivo adulterado nesses campos não mudaria a impressão. | **Corrigido.** Ela cobre todos os campos e a rede. |
| M5 | Média | Uma sessão do assinador aberta ficava com a seed na memória indefinidamente. | **Corrigido.** Encerramento automático após 10 minutos sem interação (avisa todas as telas). |

### Proteções que já existiam e foram confirmadas

- O assinador recalcula destino, valores, troco e taxa **a partir da própria transação**. Os
  metadados da carteira online (caminhos, troco declarado) servem só como dica e são conferidos
  contra a seed.
- BTC: cada entrada precisa pertencer à seed. O valor de cada entrada vem da transação de
  origem completa, conferida pelo txid. Um troco declarado falsamente aparece como envio a
  terceiros.
- ETH: chainId conferido contra a rede do arquivo; só EIP-1559, sem dados (nenhum contrato);
  remetente conferido contra a seed.
- SOL: parser próprio da mensagem legacy byte a byte. Só aceita uma única instrução de
  transferência do System Program, paga pela sua conta.
- Rede trocada (teste ↔ principal) é recusada nos dois lados.

### Adendo 2026-10-24: Dash

A Dash reaproveita o mesmo código de Bitcoin, generalizado para "moedas UTXO" (`UtxoAccount`,
`UtxoBackend`). Assim, as proteções da auditoria valem para as duas moedas: SIGHASH_ALL forçado,
posse das entradas conferida contra a seed, troco conferido, alertas de taxa (acima de 50
duff/B) e checagem final da assinatura (no scriptSig, já que a Dash usa P2PKH legado).
Verificações:

- A assinatura legada foi conferida em Python (hash pré-SegWit, ECDSA, low-S, chave pública ↔
  endereço de origem, endereços "X…" e txid).
- Ataques testados: SIGHASH_NONE em Dash e PSBT de Dash rotulado como Bitcoin (confusão de moeda).
- A sincronização foi testada ao vivo no Insight (insight.dash.org, mantido pela Dash Core Group).
- Não existe testnet Dash pública disponível; o primeiro envio real deve ser de valor pequeno.

### Adendo 2026-10-27: Monero

O Monero não tem PSBT. A carteira online (só view key + chave pública de gasto) varre os blocos
no próprio computador e encontra as saídas e seus valores. Também escolhe os decoys do anel
(gamma, como o `wallet2`) e manda tudo ao assinador. O assinador destrava só as saídas desta seed,
calcula a taxa exata pelo peso da transação, assina (CLSAG + Bulletproofs+) e roda `verRctSimple`
antes de salvar. O arquivo assinado devolve as key images, para a carteira online saber o que foi
gasto. Proteções no assinador:

- **Posse:** confere P = Hs(derivação‖i)·G + B contra a seed antes de derivar a chave secreta. O
  `monero_dart` só fazia essa conferência num `assert`: em modo debug, uma entrada alheia
  derrubava o app com um erro cru.
- **Anel (novo):** exige 16 membros, índices globais estritamente crescentes, a saída real no
  índice declarado e o commitment `mask·G + valor·H` igual ao do anel. Antes, um anel fora de
  ordem gerava uma transação que os nós recusariam, e um valor declarado falso aparecia na
  revisão.
- Destino de outra rede e entrada repetida são recusados. Alertas para taxa acima de 10% do valor
  ou acima de 0,01 XMR (a taxa por byte vem da carteira online).
- Não há roubo possível alterando valores ou anel: o consenso recusa commitments que não batem
  com a blockchain. O pior caso é a transação ser rejeitada.

Verificações:

- Endereços (rede principal e stagenet) conferidos em Python, com Keccak, ed25519 e Base58
  próprios.
- Teste de ponta a ponta sem rede (`test/features/xmr/xmr_send_sign_test.dart`): cria uma saída
  real para a seed, monta um anel de 16, assina, desserializa a transação e confere que o
  destinatário decifra o valor, que o troco volta para você, que a taxa bate com a revisão e que a
  key image é a da entrada. Também cobre "enviar tudo" com duas entradas e os ataques acima.
- Varredura testada ao vivo na stagenet (stagenet.xmr-tw.org).
- **Pendente:** um envio real na stagenet, transmitido e confirmado. Faça antes de usar fundos
  reais.
- Saídas de mineração (coinbase, ex.: P2Pool) só contam como desbloqueadas após 60 confirmações;
  as demais, após 10.
- Limitações: só o endereço principal (sem subendereços), um destino por envio.

## 4. Riscos residuais (não corrigíveis no código, ou aceitos)

1. **O app é um só binário.** O assinador não usa a rede, mas o código de rede está compilado no
   mesmo programa. A garantia "frio" depende de o aparelho do assinador estar **realmente
   offline** (sem Wi-Fi/cabo, idealmente sem placa de rede).
2. **Memória do Dart.** `String` não pode ser zerada, e as bibliotecas puras em Dart copiam
   chaves para o heap durante a derivação. A seed fica em memória protegida da libsodium, mas
   cópias transitórias existem. O histórico de desfazer dos campos de texto também pode reter
   o que foi digitado até a tela fechar.
3. **Mesmo PC para online e assinador** funciona, mas deixa de ser carteira fria.
4. **Servidores públicos** veem seus endereços e seu IP (privacidade, não roubo). Ainda não há
   suporte a Tor nem a nó próprio pela interface.
5. **Solana:** o pedido expira em cerca de 1 minuto (blockhash recente). Ainda não há durable
   nonce.
6. **Build:** o AppImage não é reprodutível nem assinado. Para fundos reais, compile você mesmo a
   partir do código (`tool/build_appimage.sh`).
7. **Bibliotecas de terceiros** (`blockchain_utils`, `bitcoin_base`, `on_chain`): Dart puro, um
   mantenedor principal e, até onde sei, sem auditoria formal. A secp256k1 em Dart puro não é de
   tempo constante. Num aparelho offline, o risco de canal lateral é baixo.
8. **Entropia das Chaves de Vida:** elas são o segundo fator. Quem encontrar o backup físico da
   seed e conhecer bem você pode tentar adivinhar as respostas. Proteja a seed como se ela
   sozinha valesse tudo.

## 5. Recomendações

- Testar todo o fluxo na **rede de teste** antes de usar fundos reais.
- Assinador em um aparelho dedicado e permanentemente offline; transferência por pendrive.
- Antes de receber valores altos: **"Conferir endereço"** no assinador.
- Atualizar dependências só depois de reler as mudanças e rodar a suíte de testes. Os vetores
  independentes falham se a assinatura mudar.
- Auditoria externa antes de valores significativos (ver a limitação no topo).
