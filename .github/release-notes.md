Carteira de criptomoedas no modelo do Electrum: um **assinador frio** (offline, com as chaves) e uma **carteira online** (somente leitura), conectados por arquivos. Nada é gravado no aparelho.

> **Pré-lançamento.** Bitcoin, Ethereum, Solana e Dash já enviam. O Monero passou no teste de envio de ponta a ponta sem rede, mas o primeiro envio real na stagenet ainda não foi feito. Teste na rede de teste antes de usar fundos reais.

## Downloads

| Plataforma | Arquivo |
|---|---|
| Linux (qualquer distro) | `BrainW4llet-*-x86_64.AppImage`: `chmod +x` e execute |
| Linux (pasta) | `BrainW4llet-*-linux-x64.tar.gz`: execute `brainw4llet` |
| Windows 10/11 | `BrainW4llet-*-windows-x64.zip`: extraia e execute `brainw4llet.exe` |
| Android 7+ | `BrainW4llet-*-android.apk`: permita "instalar apps desconhecidos" |

Confira os arquivos com `SHA256SUMS`:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

Certificado de assinatura do APK (SHA-256):
`4E:50:C0:A3:48:9E:16:5F:85:94:C1:32:C9:58:5E:CB:AA:D8:A4:E9:27:DD:86:B5:EA:A8:C9:08:15:B6:C9:39`

## Segurança

- Use o assinador num aparelho **sem internet**. O app é um binário só; a garantia "frio" depende de o aparelho estar offline.
- Estes binários foram compilados nos servidores do GitHub Actions. Para guardar valores altos, compile você mesmo a partir do código.
- Auditoria e riscos residuais: [docs/AUDITORIA.md](https://github.com/aeon1911/BrainW4llet/blob/main/docs/AUDITORIA.md).
- O Windows SmartScreen pode avisar sobre "editor desconhecido": o executável não é assinado.
