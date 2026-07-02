# mxstage

Auto-mix de retorno para Behringer X32. Mantém o balanço do monitor pessoal
de um músico no palco, corrigindo drift de nível automaticamente sem operador.

## Pré-requisitos

### Flutter SDK

```bash
# Opção 1 — download direto (recomendado, sem conflitos de versão)
mkdir -p ~/development
cd ~/development
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.4-stable.tar.xz
tar xf flutter_linux_3.44.4-stable.tar.xz

# Adicionar ao PATH (bash e zsh)
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.bashrc

# Verificar
flutter --version
dart --version
```

> **Nota Arch Linux:** `yay -S flutter` conflita com `extra/dart 3.12.0`
> (o AUR exige `dart<3.12.0`). Use o download direto acima.

### Android SDK (para builds APK)

```bash
flutter doctor   # mostra o que falta
```

Instalar Android Studio ou `android-sdk` via AUR e aceitar as licenças:
```bash
flutter doctor --android-licenses
```

## Desenvolvimento

```bash
# Instalar dependências
flutter pub get

# Testes unitários (codec OSC, engine)
dart test test/

# Rodar simulador de X32 (terminal 1)
dart run tools/x32_sim.dart

# Rodar probe de diagnóstico (terminal 2)
dart run tools/probe.dart

# Build APK debug
flutter build apk --debug
```

## Arquitetura

```
lib/osc/        # codec OSC + constantes X32 (puro Dart)
lib/mixer/      # cliente UDP: descoberta, medidores, sends, reconexão
lib/engine/     # auto-mix engine (puro Dart, headless, testável)
lib/state/      # modelos + persistência
lib/ui/         # telas Flutter
tools/          # x32_sim.dart + probe.dart
test/           # testes unitários
```

## Milestones

| M  | Feature                       | Status  |
|----|-------------------------------|---------|
| M0 | Fundação OSC + simulador      | ✅ done  |
| M1 | Conexão + volume manual       | planned |
| M2 | Medidores + referência        | planned |
| M3 | Auto-Mix Engine               | planned |
| M4 | Boost + persistência + logging| planned |
| M5 | Polimento + iOS               | planned |

## Protocolo

Behringer X32 via OSC/UDP porta **10023**.
Fonte: *Unofficial X32/M32 OSC Remote Protocol* — Patrick-Gilles Maillot.
