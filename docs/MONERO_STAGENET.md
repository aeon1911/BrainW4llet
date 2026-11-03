# Primeiro envio de Monero na stagenet

Roteiro para fechar a pendência do [RETOMAR](RETOMAR.md) e da [auditoria](AUDITORIA.md): um envio
real de Monero na stagenet, transmitido e confirmado. A stagenet é uma rede paralela, com moedas
sem valor.

Pode usar o mesmo computador para o assinador e para a carteira online, porque é só um teste.

## O que foi conferido (2026-10-30)

- O nó padrão do app (`stagenet.xmr-tw.org:38081`) estava no ar, na stagenet, sincronizado, e
  aceitava as chamadas do envio: estimativa de taxa, distribuição de saídas (decoys) e `get_outs`.
- O explorador `stagenet.xmrchain.net` respondia.
- A [CypherFaucet](https://cypherfaucet.com/xmr-stagenet) parecia ativa: paga 0,01 sXMR por pedido,
  com captcha e um pedido por hora. É o que a página informa; o pedido em si não foi testado.
- O [faucet do xmr-tw](https://stagenet-faucet.xmr-tw.org/) também consta na
  [lista oficial do Monero](https://docs.getmonero.org/infrastructure/networks/), mas a página não
  confirma que funciona.

Servidores e faucets mudam. Se algo não responder, veja a lista oficial.

## Passos

### 1. Criar uma seed descartável (assinador)

1. Na tela inicial, toque em **Gerar nova seed** e anote as 24 palavras.
2. Escolha respostas simples para as Chaves de Vida. Elas valem só para este teste.

### 2. Destravar na rede de teste (assinador)

1. Abra **Assinador frio (offline)**.
2. No seletor de rede, escolha **Teste (sem valor)**, antes de tocar em Derivar.
3. Cole a seed, preencha as respostas e toque em **Derivar**. O Argon2id usa 512 MiB, então leva
   alguns segundos.
4. Confira que o endereço Monero começa com `5`.
5. Toque em **Salvar arquivo da carteira somente leitura**. Faça isso **antes** de pedir moedas no
   faucet: a varredura da carteira online começa na data de criação desse arquivo.
6. Encerre a sessão.

### 3. Abrir a carteira online

1. Abra **Carteira online** e escolha **Abrir arquivo da carteira**.
2. Selecione o `carteira-somente-leitura-….json`. Deve aparecer o aviso "Rede de TESTE: moedas sem
   valor".
3. Vá para a aba Monero. Como o arquivo é recente, a varredura é rápida.
4. Copie o endereço da seção de receber.

### 4. Pedir moedas

1. Abra a [CypherFaucet](https://cypherfaucet.com/xmr-stagenet), cole o endereço, resolva o captcha
   e peça.
2. Espere cerca de 20 minutos. As moedas só podem ser gastas após 10 confirmações, e os blocos
   levam cerca de 2 minutos.
3. Atualize a aba Monero até aparecer **Saldo desbloqueado**. Enquanto isso, a etiqueta
   "Bloqueado" mostra o valor a caminho.

### 5. Escolher o destino

- O ideal é outro endereço de stagenet seu, para ver o valor chegando: repita os passos 1 a 3 com
  uma segunda seed descartável e copie o endereço (começa com `5`).
- Enviar para o próprio endereço também serve, mas não confirma a chegada do outro lado.
- Use o endereço principal: o app não trata subendereços.

### 6. Montar o pedido (online)

1. Na aba Monero, toque em **Enviar**.
2. Preencha o destino e um valor pequeno, por exemplo `0.001`.
3. Toque em **Criar arquivo para assinar**. A tela mostra "Buscando decoys no nó…" e salva o
   pedido.

### 7. Assinar (assinador)

1. Destrave de novo na rede **Teste**, com a mesma seed e as mesmas respostas.
2. Toque em **Assinar transação (abrir arquivo)** e abra o pedido.
3. Na tela "Assinar envio de Monero", confira o destino ("Enviar para"), a taxa, o troco e as
   moedas usadas.
4. Toque em **Assinar e salvar arquivo**. O app confere a assinatura antes de salvar.

### 8. Transmitir (online)

1. Na carteira online, toque em **Transmitir**, na barra do topo.
2. Abra a transação assinada e toque em **Transmitir agora**.
3. Deve aparecer "Transmitida!" com o identificador e o link do explorador.

## O que conta como sucesso

- A transação aparece em `stagenet.xmrchain.net` e ganha confirmações.
- A moeda usada passa para "Gasta" na aba Monero, por causa das key images do arquivo assinado.
- O troco volta bloqueado e libera após 10 confirmações.
- Com uma segunda seed, ela mostra o valor recebido depois de uns 20 minutos.

Quando isso acontecer, atualize a pendência no [RETOMAR](RETOMAR.md) e na
[auditoria](AUDITORIA.md); o release pode deixar de ser pré-lançamento.

## Se falhar

- Copie a mensagem exata. A mais provável é "O nó recusou a transação: …"; o motivo depois dos
  dois-pontos mostra onde está o problema.
- O nó pode ser trocado em **Servidores públicos**. Um segundo nó de stagenet descarta problema
  do nó.

## Opcional: Android como assinador

Depois do primeiro envio, repita o passo 7 com o APK no celular em modo avião. Isso testa o
Android e o Argon2id de 512 MiB num aparelho com pouca memória. O pedido e o arquivo assinado
precisam ir e voltar por cabo ou pela nuvem.
