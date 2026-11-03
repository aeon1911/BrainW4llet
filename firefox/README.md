# BrainW4llet para Firefox (somente leitura)

Versão da **carteira online** do BrainW4llet como extensão do Firefox. Ela importa o arquivo
somente leitura exportado pelo assinador e mostra saldo, histórico e endereço de recebimento.

| Moeda | Saldo e histórico | Receber (endereço + QR) |
|---|---|---|
| Bitcoin (SegWit nativo) | ✅ varredura com limite de 20 endereços | ✅ próximo endereço sem uso |
| Ethereum | ✅ | ✅ |
| Solana | ✅ | ✅ |
| Dash | ✅ | ✅ próximo endereço sem uso |
| Monero | ❌ use o app (precisa varrer blocos com a view key) | ✅ |

**Não envia.** A extensão não monta nem assina transações e nunca recebe chaves que gastem. Para
enviar, use o app.

## Por que só leitura

Um navegador é o pior lugar para chaves: roda código de sites o tempo todo e recebe outras
extensões. O modelo do BrainW4llet já separa o assinador (offline, com as chaves) da carteira
online (sem chaves). Por isso a extensão é só a parte online.

## Segurança

- **Nada que gaste.** O arquivo traz a zpub/xpub e os endereços. A view key do Monero entra na
  impressão digital e é descartada logo depois: a extensão não a guarda.
- **Impressão digital igual à do app.** Confira que ela é a mesma que o assinador mostra.
- **Armazenamento.** Por padrão a carteira fica só na sessão (`storage.session`) e some quando o
  Firefox fecha. "Lembrar neste navegador" grava em `storage.local`. A zpub não gasta, mas revela
  todos os seus endereços e o histórico. Trate como dado privado.
- **Rede restrita.** Só fala com os servidores listados em `lib/net.js`, que são os mesmos do
  `manifest.json` (`host_permissions` e `connect-src` da CSP). O cliente recusa qualquer outro
  host, só aceita HTTPS, não segue redirecionamentos, não envia cookies e limita o tempo e o
  tamanho das respostas.
- **Solana na rede principal** usa `solana-rpc.publicnode.com`, porque o RPC oficial responde 403
  a pedidos vindos de navegador.
- **Sem dependências.** Tudo é JavaScript próprio, sem build e sem bibliotecas de terceiros:
  BIP-32 público, secp256k1 (só operações públicas), RIPEMD-160, Base58, Bech32 e QR code.
  SHA-256 e HMAC-SHA512 vêm do WebCrypto.
- **Sem `innerHTML`.** O DOM é montado com `createElement`. Nenhum texto vindo de servidor vira
  HTML.
- **Endereço de recebimento.** Antes de receber valores altos, confira no assinador
  ("Conferir endereço"). Uma máquina online comprometida pode trocar o endereço.

## Testes

```bash
node firefox/test/tests.js
```

Também dá para abrir no navegador:

```bash
python3 -m http.server 8765 --bind 127.0.0.1 -d firefox
```

Depois, abra `http://127.0.0.1:8765/test/test.html`. Os vetores (`test/vectors.js`) vêm de um
script Python independente. Os endereços da zpub e da xpub BIP-44 da seed de teste
("abandon … about") batem com os publicados no BIP-84 e no BIP-44.

> Fora da extensão (servindo por HTTP), Bitcoin e Dash falham por CORS. Dentro da extensão, as
> `host_permissions` liberam esses servidores.

## Instalar

1. Gere o pacote:

   ```bash
   ./tool/build_firefox.sh
   ```

   Ele sai em `build/firefox/BrainW4llet-<versão>-firefox.xpi`, com o SHA-256 ao lado. O mesmo
   código gera sempre o mesmo arquivo.

2. **Para testar:** abra `about:debugging#/runtime/this-firefox` → "Carregar extensão
   temporária…" → escolha `firefox/manifest.json`. A extensão some quando o Firefox fecha.
3. **Para instalar de vez:** o Firefox comum só instala extensões assinadas pela Mozilla. Envie o
   `.xpi` ao addons.mozilla.org como **não listada** (só você recebe o arquivo assinado). Outra
   opção:

   ```bash
   npx web-ext sign --channel=unlisted --source-dir firefox
   ```

   Esse comando precisa das chaves de API do AMO.

## Versão

`version` no `manifest.json` acompanha a do `pubspec.yaml`. O workflow de release recusa a tag
se as duas forem diferentes.
