# Retomar o projeto (estado em 2026-10-28)

## Onde parou

- **Versão publicada:** [v0.1.0](https://github.com/aeon1911/BrainW4llet/releases/tag/v0.1.0), um pré-lançamento com Linux (AppImage e tar.gz), Windows (zip) e Android (APK assinado).
- **`main`:** tem tudo (PR #1 mergeado): Monero com envio air-gapped, redesign da interface e workflow de release.
- **Testes:** 94 passando; `flutter analyze` limpo.

### Pendências

1. **Primeiro envio real de Monero na stagenet**, transmitido e confirmado. Depois disso, o release pode deixar de ser pré-lançamento.
   1. Destrave o assinador na rede de **Teste**.
   2. Pegue moedas num faucet da stagenet.
   3. Envie, assine e transmita.
2. Abrir o app no Windows e no Android (até aqui, só foi aberto no Linux).
3. Ideias para depois: subendereços Monero, tokens ERC-20/SPL, transferência por QR, durable nonce na Solana e Tor/nó próprio.

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

## Chave de assinatura do Android

- O certificado tem SHA-256 `4E:50:C0:A3:48:9E:16:5F:85:94:C1:32:C9:58:5E:CB:AA:D8:A4:E9:27:DD:86:B5:EA:A8:C9:08:15:B6:C9:39`.
- O CI usa os secrets do repositório: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` e `ANDROID_KEY_ALIAS`. Eles continuam no GitHub; nada a refazer.
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

O workflow `.github/workflows/release.yml` roda os testes, compila as três plataformas, confere a assinatura do APK e publica o release com `SHA256SUMS`. Em pull requests, ele só compila.

## Histórico das conversas com o Claude Code

Há uma cópia em `/media/aeon/STEAM/Backups/BrainW4llet/claude-projects/`. Para retomar a conversa na distro nova:

1. Instale o Claude Code.
2. Copie as pastas de volta:

   ```bash
   mkdir -p ~/.claude/projects && cp -a /media/aeon/STEAM/Backups/BrainW4llet/claude-projects/. ~/.claude/projects/
   ```

3. Abra o projeto no mesmo caminho (`/media/aeon/STEAM/Projetos/BrainW4llet`). O caminho precisa ser idêntico, porque as pastas são nomeadas por ele.

Mesmo sem o histórico, este arquivo, o [README](../README.md) e a [auditoria](AUDITORIA.md) bastam para continuar.
