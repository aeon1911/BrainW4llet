# BrainW4llet

Carteira de criptomoedas pessoal no modelo do **Electrum**: um **assinador frio** (offline, com as
chaves) e uma **carteira online** (somente leitura, sem chaves), conectados por arquivos.
Nada é gravado no aparelho: a carteira é a combinação de uma seed BIP-39 aleatória de 24
palavras com as "Chaves de Vida" (respostas pessoais → Argon2id → passphrase BIP-39).

| Moeda | Ver saldo e histórico | Receber | Enviar |
|---|---|---|---|
| Bitcoin (SegWit nativo) | ✅ | ✅ | ✅ PSBT |
| Ethereum (ETH nativo) | ✅ | ✅ | ✅ EIP-1559 |
| Solana (SOL nativo) | ✅ | ✅ | ✅ |
| Dash, Monero | só dados somente leitura | — | em desenvolvimento |

## Documentos

- **Auditoria de segurança:** [docs/AUDITORIA.md](docs/AUDITORIA.md)
- Avaliação de segurança e decisões de arquitetura: [docs/AVALIACAO_SEGURANCA.md](docs/AVALIACAO_SEGURANCA.md)
- Especificação criptográfica congelada: [lib/core/security/README.md](lib/core/security/README.md)

## Compilar e testar

```bash
flutter test
```

```bash
./tool/build_appimage.sh
```

> Projeto pessoal, sem garantia. Teste na rede de teste antes de usar fundos reais.
