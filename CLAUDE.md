# MXWise — Auto-Mix de Retorno (Behringer X32)

App Flutter/Dart que mantém o balanço do monitor pessoal de um músico na X32,
corrigindo drift de nível com um loop de Auto-Mix que segura cada instrumento no
alvo do estilo (ver [Auto-Mix Engine](#auto-mix-engine)).

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

## Auto-Mix Engine

Modelo de compensação (`lib/engine/auto_mix_engine.dart`):

    send(ch) = C + master + alvo(instrumento) + boost − medidor(ch)

Mantém o nível de cada canal **no fone** constante: se o músico toca mais alto
(medidor sobe), o send desce na mesma medida; se toca mais baixo, o send sobe.
`C` é semeado na ativação (preserva o balanço atual, sem pulo) e fica **fixo** por
padrão (`refFollowSeconds → ∞`) — uma subida uniforme de toda a banda é ducked, não
acompanhada. `master` é o "volume geral" do músico (desloca o monitor todo sem
mexer no balanço entre canais).

**Alvo por instrumento** vem de `lib/state/genre_presets.dart`: `kBaseProfile`
(balanço neutro relativo à voz, âncora 0 dB) + `kGenreDeltas` (tempero por estilo).
O estilo só nuança o balanço neutro — nunca o sobrescreve.

**Gate relativo:** um canal só participa se estiver dentro de `activeRangeDb`
(40 dB) do canal mais alto do tick, e nunca abaixo de `silenceFloorDb` (−65 dB
absoluto). Silêncio real congela o canal — o Auto-Mix segura o que já está no
monitor, nunca "abre" (des-muta) um canal puxado pra baixo. Cadência: tick de
`kCorrectionIntervalMs` (1000 ms); o medidor do engine é uma **RMS de ~3 s**
(`lib/mixer/meter_stream.dart`). A média é no **domínio de potência** (amplitude²),
não em dB — senão fontes picotadas (skank de reggae, batida de bateria) leem
15–20 dB abaixo do real e o engine duca de menos, deixando-as altas no fone.

**Manter a estrela no topo:** quando o canal de maior alvo (normalmente a voz)
cai tanto que o teto do send (+10 dB) não consegue mais levantá-lo até o alvo,
subir os demais até *os alvos deles* enterraria a voz. Em vez disso o engine
**abaixa a referência** por tick (`effectiveRef = C − duck`) pela diferença, então
a banda inteira desce junto e o balanço do estilo é preservado (voz por cima) —
limitado por `maxDuckDb` (12 dB) pra um canal quase-mudo não derrubar a mix toda.
É o "corta o resto quando não dá pra subir a estrela". `_refLevelDb` guarda o `C`
sem o duck (continuidade de seed/log).

**Seed robusto:** o `C` **não** é travado no primeiro instante da ativação. Se o
Auto-Mix é ligado antes da banda estar tocando de verdade, os medidores mostram um
quadro **achatado** (todos os canais quase no mesmo nível — padrão do fader/UI antes
do áudio), e semear ali trava um `C` alto que **estrangula o mix inteiro** (todo mundo
quer boost gigante, bate no teto, "some"). Então o engine **segura** (`update` devolve
`[]`) enquanto ≥`seedMinChannels` (3) canais estão ativos mas o espalhamento
(mais alto − mais baixo) é < `seedMinSpreadDb` (5 dB) — nenhuma banda real é tão
plana. Semeia assim que aparece espalhamento real, ou no máximo após
`seedMaxWarmupTicks` (15). Com <3 canais ativos, semeia na hora (solo/duo não tem
espalhamento pra julgar). Isso foi confirmado num log real: a ativação "cedo demais"
travava `C=-1,9` e faminto; com o fix, segura 5 ticks e semeia em `C≈-15` com o
balanço do estilo cravado.

**Premissa de tuning — fones-only (IEM no Stage, headphone na Live).** Sem caminho
acústico do monitor de volta pro microfone não há microfonia, então o motor é
agressivo pra cravar cada instrumento no alvo do estilo ("jogar no talo"): em
`EngineParams`, teto `sendCeilingDb` +10 dB, boost até `maxBoostDb` 24 dB, slew
`maxStepDb` 4 dB/s. A única proteção de boost que sobra é a **guarda adaptativa**
(`boostRampDb` 25 dB): o boost cheio só é liberado enquanto o canal está bem acima
do piso de ruído, recuando perto do silêncio — assim não amplifica chiado/vazamento
de um canal quase mudo.

> **Se algum dia acionar PA ou caixa de retorno de palco (wedge):** o caminho de
> feedback volta — reduza `sendCeilingDb` pra 0 dB e `maxBoostDb` pra ~9–12 dB
> **antes**. O certo a médio prazo é virar um profile nomeado
> (`EngineParams.inEar()` / `.wedge()`) com seletor na UI, não um default global.

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

**Escala do float do medidor:** o app trata cada float como **amplitude linear**
(0..1) e faz `20·log10` (`MeterStream`). O simulador manda exatamente isso (RMS
linear pós-fader). ⚠️ `// CONFIRM AGAINST REAL HARDWARE`: se a X32 real mandar o
medidor **já em dB normalizado** (ex.: `(dBFS+50)/50`), o app o releria como
amplitude (duplo-log) e **comprimiria a escala ~4×** — o Auto-Mix "não veria" o
quanto cada fonte sobe/desce. Já mordeu no sim (era `(db+50)/50`, corrigido pra
linear). Se acontecer na mesa real, inverter a decodificação no `MeterStream`.
