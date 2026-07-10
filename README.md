# MXWise

Auto-mix de retorno para Behringer X32. Mantém o balanço do monitor pessoal
de um músico no palco, corrigindo drift de nível automaticamente sem operador.

Além do monitor do músico (**Stage**), o mesmo Auto-Mix atende a mix da
**transmissão** (Live/YouTube) — ver [Modos](#modos-stage-e-live).

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

## Modos: Stage e Live

O app abre direto na descoberta da mesa. No seletor de bus, além dos monitores,
há uma entrada **Live** (protegida por PIN) para a mix da transmissão.

- **Stage** — monitor pessoal do músico. Escolhe seu bus de retorno e o Auto-Mix
  mantém o balanço. Uso padrão, aberto.
- **Live** — mix dedicada da transmissão (YouTube). Entrada protegida por PIN.
  O bus da Live é resolvido nesta ordem:
  1. um bus **nomeado** `Live`/`Transmissão`/`Stream`/… na própria mesa;
  2. o último bus lembrado;
  3. designação manual (uma vez) — botão "trocar" na entrada Live re-designa.

O núcleo (`MixerClient` + engine + faders) é agnóstico ao modo — só muda o bus
alvo, o portão de entrada e a apresentação. Um bus é apenas um destino de mix: a
Live é um **MixBus dedicado** roteado pra placa de streaming; o caminho OSC é
idêntico ao de um monitor (`/ch/NN/mix/MM/level`).

**Segurança (build de teste):** o PIN (`kLivePin`, hoje fixo `7733`) é temporário
— previne acidente/curiosidade, não é barreira real (o X32 não autentica cliente
na rede). O bus da Live fica escondido do seletor do Stage, então o músico não o
seleciona. Direção futura: provisionamento por device com tokens assinados.
PA/FOH está fora de escopo.

**Setup na mesa:** dedique um bus livre à transmissão, roteie-o pra sua placa/
saída de streaming e **nomeie-o `Live`** — o app o reconhece sozinho. (O
simulador `tools/x32_sim.dart` já traz o bus 16 nomeado `Live` para teste.)

## Milestones

| M  | Feature                       | Status          |
|----|-------------------------------|-----------------|
| M0 | Fundação OSC + simulador      | ✅ done          |
| M1 | Conexão + volume manual       | ✅ done          |
| M2 | Medidores + referência        | ✅ done          |
| M3 | Auto-Mix Engine               | ✅ done          |
| M4 | Boost + persistência + logging| 🚧 em progresso  |
| M5 | Polimento + iOS               | 🚧 em progresso  |
| —  | Modos Stage/Live (transmissão)| ✅ build de teste (PIN fixo) |

## Protocolo

Behringer X32 via OSC/UDP porta **10023**.
Fonte: *Unofficial X32/M32 OSC Remote Protocol* — Patrick-Gilles Maillot.
