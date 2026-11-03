# Instruções para agentes (IA)

BrainW4llet é uma carteira de criptomoedas em Flutter, no modelo do Electrum: um **assinador
frio** (offline, com as chaves) e uma **carteira online** (somente leitura), ligados por arquivos.

**Leia primeiro [docs/RETOMAR.md](docs/RETOMAR.md):** estado atual, pendências em ordem, o ciclo
commit → CI → instalar no Waydroid e as armadilhas já pisadas. Depois, o [README](README.md) e a
[auditoria](docs/AUDITORIA.md).

## Como trabalhar

- **Idioma:** português, com o usuário, nos commits e nos documentos.
- **Autonomia:** o usuário pediu que você aja sem ficar perguntando (acompanhar o CI, baixar o APK,
  instalar). Pare e pergunte só para: senhas e credenciais (ele digita), mesclar um PR, qualquer
  coisa com fundos reais e ações destrutivas ou irreversíveis.
- **Não há Flutter, JDK, Android SDK nem `gh` na máquina atual.** A verificação é o CI do GitHub
  (`.github/workflows/release.yml`). `flutter analyze` falha com avisos e infos, então siga o
  `flutter_lints` do projeto (locais `final`, `const` onde der, nada de `print`).
- **Confira o SHA-256** de todo artefato baixado contra o digest mostrado pelo GitHub antes de
  instalar.
- Trabalhe em branch e PR; não faça push na `main` nem mescle por conta própria.

## Regras de segurança do produto (não quebre)

- Nada de seed, chave privada ou resposta das "Chaves de Vida" em disco, log ou área de
  transferência. O lint `avoid_print` é erro de propósito.
- O assinador frio nunca usa a rede; só a carteira online tem clientes de rede.
- Pacotes criptográficos ficam em **versões exatas** (`pubspec.yaml`), e o Argon2id não pode ser
  enfraquecido. Especificação: [lib/core/security/README.md](lib/core/security/README.md) e
  [docs/AVALIACAO_SEGURANCA.md](docs/AVALIACAO_SEGURANCA.md).
- Acrescentar um servidor público é mudar quem vê os endereços do usuário: registre no aviso da
  tela e em [docs/AUDITORIA.md](docs/AUDITORIA.md).
