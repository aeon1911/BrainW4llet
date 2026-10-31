# Retomar o projeto (estado em 2026-10-31)

Quem assume (pessoa ou IA): comece por aqui. As regras curtas de trabalho estão em
[AGENTS.md](../AGENTS.md). O usuário fala português e prefere que você tome as decisões e
siga em frente, sem ficar perguntando.

## Estado atual

- **Versão publicada:** [v0.1.0](https://github.com/aeon1911/BrainW4llet/releases/tag/v0.1.0), pré-lançamento com Linux (AppImage e tar.gz), Windows (zip) e Android (APK assinado).
- **`main`** (`38ec40c`): Monero com envio air-gapped, redesign e workflow de release (PR #1).
- **[PR #2](https://github.com/aeon1911/BrainW4llet/pull/2) aberto, não mesclado**, branch `fix/android-salvar-arquivo`, CI verde. Torna o app utilizável no Android, testado no **Waydroid** (LineageOS 20, Android 13, só IPv4). Com ele o usuário já abre uma carteira e chega às abas Bitcoin e Monero, mas ainda não confirmou que as duas correções mais recentes (Bitcoin e Monero) funcionam.
- **Testes:** `flutter analyze` e `flutter test` passam no CI. Não há Flutter nesta máquina (ver abaixo).

### O que o PR #2 faz

| Commit | Mudança |
|---|---|
| `6c6a159` | **Salvar** no Android pelo diálogo nativo "Salvar como". O `file_selector` não suporta salvar no Android e o erro era engolido (o botão parecia não fazer nada). |
| `d48552e` | **Abrir** pelo seletor nativo, fora da thread principal, limite de 8 MiB, falha vira mensagem (antes o plugin deixava um NullPointerException do Android derrubar o app). |
| `092f445`, `ed5a44b`, `a94c123` | **Modo compatível:** no Waydroid, o provedor de arquivos do Android falha na leitura normal (NPE no MediaProvider). O app detecta o Waydroid e abre o descritor em `rw`, só lendo. Em outros aparelhos o modo é oferecido depois de uma falha ("Escolher de novo"). A ideia de ler da pasta do app (`092f445`) foi abandonada em `ed5a44b`/`a94c123`: a pasta é inalcançável sem root. |
| `ee68ded` | **Bitcoin:** `FailoverEsplora` tenta mempool.space, depois mempool.emzy.de e mempool.bullbitcoin.com (testnet4: mempool.space, depois emzy). O mempool.space não completa a conexão por IPv4 em algumas redes e o Waydroid só tem IPv4, então a aba dava timeout. Só falha de conexão, tempo esgotado e 5xx trocam de servidor. |
| `39a6463` | **Monero:** a varredura dava ANR no Android. O Dart roda na thread principal e o gerador `scanBlock` da `monero_dart` processa blocos sem voltar ao laço de eventos. Agora o laço cede o controle a cada bloco. |
| `3ee34ee` | **CI:** job `ios` gera o IPA sem assinatura como artefato. É `continue-on-error` e não é exigido pelo release. |
| `790ba18` | Roteiro [docs/MONERO_STAGENET.md](MONERO_STAGENET.md). |

## Pendências, em ordem

1. **Usuário validar no Waydroid** o APK mais recente (commit `39a6463`, hash do `base.apk` `7a186211…`): a aba Bitcoin carrega (a primeira consulta espera ~8 s pelo mempool.space falhar) e a varredura do Monero termina sem o aviso "o app não está respondendo". Se o Android ainda mostrar o aviso, é porque algum bloco isolado passa de 5 s: o caminho é varrer num isolate.
2. **Mesclar o PR #2** quando o usuário confirmar. A descrição do PR não cita o job `ios` nem o roteiro da stagenet.
3. Depois do merge, publicar `v0.1.1` (ver "Publicar uma versão nova").
4. **Primeiro envio real de Monero na stagenet** ([roteiro](MONERO_STAGENET.md)). Use a rede **Teste**: o arquivo `carteira-somente-leitura-0F98-BE0A.json` que o usuário tem no Waydroid é de mainnet (o `tentativa.json`, criado depois, não foi conferido). Depois disso o release pode deixar de ser pré-lançamento.
5. **Risco conhecido:** a assinatura Monero no assinador (CLSAG + Bulletproofs+) é pesada e roda na thread principal. No Android pode dar o mesmo ANR; o caminho é assinar num isolate (cuidado com a seed: ela vive em memória protegida da libsodium).
6. `saveTextFile` em `lib/presentation/widgets/file_io.dart` lança `PlatformException` no Android e nenhuma das seis telas que salvam trata isso: uma falha ao gravar continua sem mensagem.
7. **iOS:** o artefato `ios` do CI é um IPA sem assinatura (`BrainW4llet-0.1.0-ios-unsigned.ipa`). Nunca foi instalado num iPhone. O usuário assina com o Apple ID pelo SideStore/AltStore (certificado de 7 dias). Assinar no CI exigiria certificado e perfil nos secrets do GitHub; o usuário não deu isso.
8. Ideias para depois: subendereços Monero, tokens ERC-20/SPL, transferência por QR, durable nonce na Solana, Tor e nó próprio.

Limpeza opcional: branches locais `docs/monero-stagenet` (o commit foi levado ao PR como `790ba18`) e `claude/projeto-monero-implementation-aa53b0` (igual à `main`); pastas `~/Downloads/BrainW4llet-pr2-android-v*` e `~/Downloads/BrainW4llet-ios-unsigned`; no Waydroid, o JSON que foi copiado para
`~/.local/share/waydroid/data/media/0/Android/data/com.brainw4llet.brainw4llet/files/` (o app não usa mais).

## Como trabalhar nesta máquina

O projeto está em `/mnt/STEAM/Projetos/BrainW4llet` (os trechos abaixo sobre "máquina nova" falam em `/media/aeon/STEAM/...`). Esta máquina é Linux e **não tem Flutter, JDK, Android SDK nem `gh`**: você não compila nem roda testes aqui. Tudo passa pelo CI do GitHub.

### Ciclo commit → CI → instalar no Waydroid

1. Commit e `git push` na branch do PR (sem `gh`; o push funciona com as credenciais do usuário).
2. O workflow `Release` roda em PR: análise e testes (~3 min), depois Linux, Windows, Android e iOS (total ~8 min). **`flutter analyze` falha com qualquer aviso ou info**, então um lint quebra o CI.
3. Acompanhe a execução no navegador embutido do app (já logado no GitHub): `https://github.com/aeon1911/BrainW4llet/actions?query=branch%3Afix%2Fandroid-salvar-arquivo`. O usuário já avisou que o CI terminou antes da hora várias vezes: confira você mesmo o estado da execução. Para esperar, use um `sleep` em segundo plano (`run_in_background`); `sleep` em primeiro plano é bloqueado.
4. Na página da execução, pegue o digest SHA-256 do artefato `android` (o zip) e baixe navegando para `…/actions/runs/<id>/artifacts/<id>`. O navegador grava em `~/Downloads` com nome oculto (`.org.chromium.Chromium.XXXX`) ou aleatório (`a.zip`, `barat.zip`…). O download **às vezes trava ou não começa**: se o tamanho parar de crescer, apague o arquivo parcial (confirme que nenhum processo o mantém aberto) e tente de novo. Só use o zip se o `sha256sum` bater com o digest.
5. Extraia numa pasta nova, confira o `android.sha256` interno e instale:

   ```bash
   waydroid app install ~/Downloads/<pasta>/BrainW4llet-0.1.0-android.apk
   ```

   Sai sem mensagem e **aplica em segundo plano**; às vezes é preciso repetir. Para confirmar, compare o hash do `base.apk` instalado (precisa de root, veja abaixo) com o do APK.
6. Abrir o app: `waydroid app launch com.brainw4llet.brainw4llet` (ou `waydroid show-full-ui`).

### Root e logs do Waydroid

Comandos com `sudo` rodam no terminal do usuário (`mcp__terminal__run_in_terminal`; ele aprova e digita a senha se pedir), com a saída redirecionada para um arquivo do scratchpad que você lê depois:

```bash
sudo waydroid shell -- logcat -d -b main,system,crash -t 4000 > <scratchpad>/log.txt
sudo waydroid shell -- sh -c 'sha256sum /data/app/*/com.brainw4llet.brainw4llet-*/base.apk'
sudo waydroid shell -- sh -c 'cat $(ls -t /data/anr/anr_* | head -1)'   # pilhas de um ANR
```

Procure `FATAL EXCEPTION`, `ANR in` e `Input dispatching timed out`. O app roda como `u0a138` (uid 10138). A pasta compartilhada do Waydroid no host (`~/.local/share/waydroid/data/media/0`) só abre com `sudo`.

### Armadilhas já pisadas

- **Dart roda na thread principal do Android.** Trabalho pesado sem voltar ao laço de eventos (microtasks, `async*` sem I/O real) passa de 5 s e vira ANR. Ceda controle (`await Future.delayed(Duration.zero)`) ou use um isolate.
- **Waydroid só tem IPv4.** Servidores acessíveis só por IPv6 (ou com IPv4 bloqueado na rede do usuário, como o mempool.space e o blockstream.info) dão timeout lá.
- **O provedor de arquivos do Android falha no Waydroid** na leitura em modo `r` (NPE em `MediaProvider`/`AppOpsService.checkPackage`). Por isso o modo compatível existe; não o remova.
- **`SessionGuard`** apaga a sessão do assinador quando o app vai para segundo plano. Abrir o seletor de arquivos do sistema conta como isso: depois de escolher o arquivo, o assinador pode precisar ser destravado de novo.
- O `shell` do Waydroid não tem `su`.
- Nunca digite senha ou credencial pelo usuário (login do GitHub, sudo, Apple ID). Peça que ele faça.

### Mapa do código tocado no PR #2

- `android/app/src/main/kotlin/com/brainw4llet/brainw4llet/MainActivity.kt`: canal `com.brainw4llet.brainw4llet/files` (`saveText`, `openText`), detecção do Waydroid.
- `lib/presentation/widgets/file_io.dart`: `pickTextFile(context)`, `saveTextFile`, `ReadFailedDialog`.
- `lib/features/btc/esplora_client.dart` (`FailoverEsplora`), `lib/features/network/http_json.dart` (`NetworkException.retryable`), `endpoints.dart`.
- `lib/features/xmr/xmr_wallet.dart`: `XmrWatcher.sync`.
- `.github/workflows/release.yml`: job `ios`.
- Testes novos: `test/presentation/file_io_dialog_test.dart`, `test/features/btc/esplora_failover_test.dart`.

## Preparar uma máquina nova

### 1. Dependências do sistema (Ubuntu/Pop!_OS/Debian)

```bash
sudo apt-get install -y git clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libstdc++-14-dev librsvg2-bin desktop-file-utils
```

Instale também `libstdc++-14-dev`: o clang escolhe o GCC mais novo instalado e falha com `cannot find -lstdc++` se faltar a biblioteca dele. Sem esse pacote, há um contorno que aponta o clang para o GCC 13:

```bash
export CXXFLAGS=--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/13 CFLAGS=--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/13
```

### 2. Flutter 3.47.8 (a mesma versão do CI)

```bash
mkdir -p ~/development && cd ~/development && curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz
```

```bash
cd ~/development && echo "baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2  flutter_linux_3.47.8-stable.tar.xz" | sha256sum -c && tar xf flutter_linux_3.47.8-stable.tar.xz
```

Depois, coloque `~/development/flutter/bin` no `PATH`.

### 3. Projeto

```bash
cd /media/aeon/STEAM/Projetos/BrainW4llet && git pull && flutter pub get --enforce-lockfile && flutter test
```

```bash
flutter run -d linux
```

### 4. GitHub CLI

```bash
gh auth login
```

Com o `gh` instalado e autenticado, abrir PRs, editar a descrição e baixar artefatos (`gh run download`) fica bem mais simples do que o navegador embutido.

## Chave de assinatura do Android

- O certificado tem SHA-256 `4E:50:C0:A3:48:9E:16:5F:85:94:C1:32:C9:58:5E:CB:AA:D8:A4:E9:27:DD:86:B5:EA:A8:C9:08:15:B6:C9:39`.
- O CI usa os secrets do repositório: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` e `ANDROID_KEY_ALIAS`. Eles continuam no GitHub; nada a refazer. PRs do próprio repositório recebem os secrets, então o APK do PR sai com a chave de release e instala por cima do anterior.
- **Cópia local fora do git:** `/media/aeon/STEAM/Backups/BrainW4llet/BrainW4llet-android-release/` (keystore `.p12` + senha). Mantenha também um backup offline. Sem a chave, nenhuma versão nova instala por cima da atual.
- Para assinar localmente, crie `android/key.properties` (ignorado pelo git):

  ```properties
  storeFile=/media/aeon/STEAM/Backups/BrainW4llet/BrainW4llet-android-release/brainw4llet-release.p12
  storePassword=<conteúdo de store-password.txt>
  keyAlias=brainw4llet
  ```

## Publicar uma versão nova

1. Suba `version:` no `pubspec.yaml` (ex.: `0.1.1+2`).
2. Faça commit na `main`.
3. Crie e envie a tag com o mesmo número:

   ```bash
   git tag -a v0.1.1 -m "BrainW4llet v0.1.1" && git push origin v0.1.1
   ```

O workflow `.github/workflows/release.yml` roda os testes, compila as três plataformas, confere a assinatura do APK e publica o release com `SHA256SUMS`. Em pull requests, ele só compila. O job `ios` ainda não entra no release.

## Histórico das conversas com o Claude Code

Há uma cópia em `/media/aeon/STEAM/Backups/BrainW4llet/claude-projects/`. Para retomar a conversa na distro nova:

1. Instale o Claude Code.
2. Copie as pastas de volta:

   ```bash
   mkdir -p ~/.claude/projects && cp -a /media/aeon/STEAM/Backups/BrainW4llet/claude-projects/. ~/.claude/projects/
   ```

3. Abra o projeto no mesmo caminho (`/media/aeon/STEAM/Projetos/BrainW4llet`). O caminho precisa ser idêntico, porque as pastas são nomeadas por ele.

Mesmo sem o histórico, este arquivo, o [README](../README.md) e a [auditoria](AUDITORIA.md) bastam para continuar.
