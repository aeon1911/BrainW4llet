# PROMPT MESTRE: Multiplatform Secure Stateless Crypto Wallet (Flutter)

## 1. Visão Geral e Objetivo do Projeto
Construir uma carteira de criptomoedas 100% *stateless* e multiplataforma (iOS, Android, Windows, macOS e Linux) usando **Flutter**. 
O aplicativo não deve possuir servidores backend (é totalmente descentralizado e direto na RPC da blockchain) e **nunca** armazena chaves privadas, frases mnemônicas ou dados sensíveis em disco, banco de dados local ou cache persistente.

---

## 2. Requisito Crítico de Segurança: Derivação de Chaves ("Chaves de Vida")
O usuário acessará a carteira informando dados estritamente pessoais de sua vida (perguntas/respostas secretas). Como o uso direto de *Brainwallets* puras é vulnerável a ataques de força bruta, a arquitetura de segurança obrigatória deve seguir rigorosamente estas regras:

1. **Normalização de Entrada (Input Sanitization):**
   - Antes de qualquer processamento criptográfico, as respostas do usuário devem ser normalizadas: conversão estrita para letras minúsculas (lowercase), remoção de acentos (diacríticos) e remoção de espaços extras nas extremidades ou múltiplos espaços internos.
2. **Derivação Criptográfica com Argon2id:**
   - **PROIBIDO** usar hashes simples (SHA-256, MD5 ou RIPEMD) diretamente nas respostas do usuário.
   - Utilize a biblioteca `cryptography` para derivar uma *Seed/Entropy* criptográfica robusta a partir das strings normalizadas usando o algoritmo **Argon2id**.
   - Defina parâmetros de custo altos e seguros para dificultar força bruta:
     - `memoryCost`: mínimo de 65536 (64 MB) ou superior.
     - `timeCost`: mínimo de 3 a 5 iterações.
     - `parallelism`: 2 ou superior.
     - `outputLength`: 32 bytes (256 bits).
3. **Padrão BIP-39 / BIP-44 (HD Wallet):**
   - A saída de 32 bytes gerada pelo Argon2id deve ser tratada como entropia mnemônica ou passada por derivação BIP-39 para gerar as 12/24 palavras padrão da carteira, garantindo compatibilidade com o ecossistema cripto (EVM, Bitcoin, Solana), opcionalmente permitindo uma *passphrase* estendida.
4. **Ciclo de Vida em Memória RAM (Zero-Persistence):**
   - As chaves privadas (`PrivateKey`), sementes e o hash derivado devem existir **exclusivamente em memória RAM (variáveis voláteis)**.
   - Assim que o usuário fechar o aplicativo ou o app for minimizado/ir para segundo plano (`AppLifecycleState.paused` / `detached`), limpe imediatamente todas as referências de memória sensíveis. **Nenhum arquivo de log deve imprimir chaves ou dados de entrada.**

---

## 3. Stack Tecnológica e Arquitetura do Código
- **Framework:** Flutter (versão estável mais recente).
- **Gerenciamento de Estado:** Provider, Riverpod ou Bloc (mantenha limpo e desacoplado).
- **Pacotes Obrigatórios no `pubspec.yaml`:**
  - `cryptography` (para Argon2id e AES-GCM em memória).
  - `bip39` e `bip32` (para gerenciamento de chaves determinísticas).
  - `web3dart` (para interação com redes EVM - Ethereum, Polygon, BSC).
  - `flutter_secure_storage` (apenas para configurações de UI não-sensíveis ou preferências de rede RPC, **nunca** para guardar chaves).
- **Estrutura de Pastas Sugerida:**
  - `/lib/core/security/` (Lógica de Argon2id, normalização e limpeza de memória).
  - `/lib/features/wallet/` (Lógica de assinatura de transações e saldo).
  - `/lib/presentation/` (Telas limpas para iOS, Android e Desktop com design responsivo).

---

## 4. Diretrizes para o Agente de IA (Claude Code / Antigravity)
- **Autonomia de Execução:** Use os comandos de terminal disponíveis para inicializar o projeto (`flutter create .`), instalar dependências e rodar testes estáticos.
- **Tratamento de Erros:** Se um pacote falhar na compilação cruzada (especialmente em nativo/FFI), procure alternativas puras em Dart ou ajuste o `pubspec.yaml` com compatibilidade multiplataforma confirmada.
- **Portabilidade:** Mantenha o código modular para que, se houver troca de IDE/Agente, o próximo contexto entenda exatamente onde a criptografia e a UI estão separadas.
