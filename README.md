# BrainW4llet

Cold wallet pessoal, sem persistência, em Flutter. A carteira é a combinação de
uma seed BIP-39 aleatória de 24 palavras com as "Chaves de Vida" (respostas
pessoais → Argon2id via libsodium → passphrase BIP-39). Nada é gravado no aparelho.

- Avaliação de segurança e decisões: [docs/AVALIACAO_SEGURANCA.md](docs/AVALIACAO_SEGURANCA.md)
- Especificação criptográfica (congelada): [lib/core/security/README.md](lib/core/security/README.md)
- IPA de teste (AltStore): workflow `ios-unsigned-ipa` em [codemagic.yaml](codemagic.yaml)

```bash
flutter test
```
