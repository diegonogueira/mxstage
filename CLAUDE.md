# MXWise — Auto-Mix de Retorno (Behringer X32)

App Flutter/Dart que mantém o balanço do monitor pessoal de um músico na X32,
corrigindo drift de nível com um loop de Auto-Mix baseado em referência capturada.

## Invariantes de segurança (nunca violar)

1. O app escreve **somente** em `/ch/NN/mix/MM/level` onde `MM` é o bus selecionado
   pelo usuário. Nunca em faders de canal (`/ch/NN/mix/fader`) nem em outro bus.
2. `lib/engine/` importa apenas `dart:core` e `dart:typed_data` — **zero Flutter, zero I/O**.
   O engine é headless e testável sem UI e sem hardware.
3. Todo I/O de socket UDP fica em `lib/mixer/` — nunca em engine, state ou ui.
4. Constantes do protocolo (porta, banco de medidores, curva de fader) vivem
   **somente** em `lib/osc/x32_protocol.dart`, marcadas com `// CONFIRM AGAINST REAL HARDWARE`.

## Estrutura

```
lib/osc/        # codec OSC + constantes X32 (puro Dart)
lib/mixer/      # cliente OSC: descoberta, medidores, sends, reconexão
lib/engine/     # auto-mix engine (puro Dart, sem Flutter, testável headless)
lib/state/      # modelos + persistência JSON (shared_preferences)
lib/ui/         # telas Flutter
tools/          # x32_sim.dart (simulador) + probe.dart (diagnóstico)
test/           # unit tests do engine e do codec
```

## Stack

- Flutter 3.44.x / Dart 3.12.x
- UDP: `dart:io` `RawDatagramSocket` (nativo, sem lib de terceiro)
- Persistência: `shared_preferences`
- Log de sessão: `path_provider` + arquivo JSONL no device

## Milestones e critérios de aceite

| M  | Feature                       | Aceite                                                   |
|----|-------------------------------|----------------------------------------------------------|
| M0 | Fundação OSC + simulador      | `probe` descobre o sim, lê nomes, mostra medidores        |
| M1 | Conexão + volume manual       | Fader no app → `/ch/NN/mix/MM/level` correto no sim log  |
| M2 | Medidores + referência        | Barras ao vivo; "Capturar" grava alvos relativos coerentes|
| M3 | Auto-Mix Engine               | Headless: surge corrige, silêncio não abre, clamp ok     |
| M4 | Boost + persistência + logging| Boost desloca alvo; replay de sessão funciona            |
| M5 | Polimento + iOS               | Culto real sem travar; APK + iOS build                   |

## Bus de retorno

Aux/Mix Bus (MixBus 1–16). Caminho de escrita: `/ch/NN/mix/MM/level ,f <0..1>`.
Ultranet/P16 está fora de escopo no MVP.

## Modos (Stage/Live)

Dois contextos, escolhidos **dentro do seletor de bus** (não em telas separadas):
`enum AppMode` em `lib/state/app_mode.dart`.

- **Stage** — padrão, aberto. Músico escolhe seu bus de retorno.
- **Live** — mix da transmissão, atrás de um PIN (`kLivePin`, hoje fixo `7733`,
  **temporário**). O bus da Live fica **escondido** do seletor do Stage para o
  músico não o pegar.

O núcleo (`MixerClient`, engine) permanece **agnóstico ao modo** — nada de "modo"
entra no cliente/engine (preserva os invariantes #1–#3). O modo só afeta a UI
(rótulo/acento/badge), o portão de PIN e qual bus é o alvo. Fluxo centralizado em
`lib/ui/widgets/live_entry.dart`.

Resolução do bus da Live: bus **nomeado** `Live`/`Transmissão`/`Stream`/… na mesa
→ último lembrado (`AppSettings.liveBus`, `shared_preferences`) → designação
manual. O PIN é anti-acidente, não segurança forte (o X32 não autentica cliente
na rede); direção futura é provisionamento por device com tokens assinados.

## Protocolo OSC X32 — referência

Fonte canônica: *Unofficial X32/M32 OSC Remote Protocol* — Patrick-Gilles Maillot.
Porta UDP: **10023**. Renovação de assinatura de medidores: a cada **5s** (expira em 10s).
Banco de medidores: `/meters/13` — 48 floats, canais de entrada nos índices 0..31.
Blob de medidores: `[count uint32 LE][N × float32 LE]` (interior LE; tamanho do blob BE, padrão OSC).
