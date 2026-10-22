# MXWise — Auto-Mix de Retorno (Behringer X32)

App Flutter/Dart que equaliza o monitor pessoal de um músico na X32: o fluxo
principal é o **Equalizar sob demanda** (ver [Equalizar](#equalizar-sob-demanda--fluxo-principal));
o loop contínuo de Auto-Mix (ver [Auto-Mix Engine](#auto-mix-engine)) fica como
opção avançada no menu.

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

## Equalizar (sob demanda) — fluxo principal

`lib/engine/equalizer_engine.dart`. Nasceu de testes reais na igreja: o Auto-Mix
contínuo é um AGC por canal — não distingue "tocando baixo" de "parado
(vazamento)", então **sobe o canal durante a pausa** e o músico **volta estourado**
(sim: guitarra +18 dB, voz +8 dB); e por só cortar os outros, deixa o **mix todo
baixo** (~6 dB). O Equalizar resolve os dois:

1. Escuta `kEqualizeMeasureMs` (15 s) amostrando o medidor rápido a 5 Hz.
2. Por canal, mede o **nível tocando** (gated): descarta piso/vazamento (−65 dB e
   >40 dB abaixo do mais alto no quadro), acha o "forte" (p95) e fica com as
   amostras até 15 dB abaixo dele; RMS em potência. <15% da janela ⇒ "não ouvido".
3. `send = K + alvo(instrumento) − nível`, com `K` tal que o maior send = 0 dB
   (empurra o mix pra cima; sobram +10 dB pro volume geral, que é limitado pela
   folga até o teto pra não quebrar o balanço). Só canais a ≤`anchorRangeDb`
   (20 dB) do mais alto definem `K` — um mic muito baixo não afunda o mix.
   **Canal de instrumento desconhecido nunca é equalizado** (fica como a mesa
   deixou) e menos de `minRoles` (2) papéis ouvidos ⇒ `tooFew`, nada aplicado.
   Log real 21/10: o DM (talkback, ruído −60 dB, "unknown") virou o topo → DM
   +10 dB e o resto ~25 dB abaixo ("MUITO baixo"); e equalizar só com o teclado
   tocando (pré-culto) travava um balanço vazio.
4. Depois **fica parado**. Estilo, reforço, volume geral e troca de instrumento
   recalculam na hora a partir dos níveis guardados (sem medir de novo). Fader
   manual vira ajuste fino (trim), não é brigado.
5. **Proteção** (opcional, escudo na UI, `AppSettings.protection`): só **abaixa**
   um canal que ficou >4 dB acima do medido (corta até +1, attack 2 dB/s,
   release 0,5 dB/s, máx. 12 dB) e devolve só até o nível equalizado. **Nada sobe
   sozinho, nunca.**
6. **Reequalizar mescla**: quem tocou é re-medido; quem estava calado mantém o
   nível (e o trim) que o engine já sabia — não volta ao send de antes e não faz o
   mix saltar. A referência fica **travada** na mescla (`_kShift`): a banda mais
   forte no refrão não sobe os lembrados (log: a guitarra lembrada subia +5 e
   ficava alta). Desligar o modo devolve os sends de antes e zera a memória.
7. **Canal no/fora do meu fone** (`ChannelInclusion`, por mesa+bus,
   `AppSettings.channelInclusions`; segurar o canal): "Como na mesa" (padrão —
   envio desligado na mesa continua desligado; o Equalizar avisa em
   `parkedOff`), "No meu fone" (`forcedIn`: inclui e equaliza mesmo desligado na
   mesa — o violão a 0,05 do log) e "Fora" (`excluded`: send 0, ignorado pelo
   Equalizar e pelo Auto-Mix; restaurar baseline não o reabre). Escritas internas
   não viram baseline.

**Meu instrumento** (`lib/state/musician_roles.dart`): o músico escolhe o *canal*
dele (por mesa+bus, `AppSettings.ownChannel`); o papel vem do instrumento desse
canal. Terceira camada do alvo: `alvo = base + estilo + papel`. O canal escolhido
sobe `kOwnChannelBoostDb` (+6; bateria +2 porque o kit todo sobe) e os outros
seguem `kRoleDeltas` (ex.: tecladista desce guitarra/piano/outro teclado −3;
baterista sobe kit e baixo; baixista sobe bumbo +4). Como o topo é normalizado em
0 dB, o "meu" vira o canal mais alto. Na Live não há papel (`ownChannel = null`,
voz como âncora). Só vale no Equalizar (o Auto-Mix contínuo ignora).
A **bateria é um conjunto**: no seletor é uma entrada só (o canal guardado é um
representante, `drumKitChannel`) e o kit inteiro sobe por `kRoleDeltas` — sem
extra no canal escolhido. O seletor esconde canais sem sinal desde a conexão
(`MixerClient.channelHeard`, limiar `kHeardThresholdDb`) e desconhecidos, com
"Mostrar todos". Sem escolha salva (`AppSettings.hasOwnChannelChoice`), a tela
sugere pelo **nome do bus** (`ownChannelFromBusName`: nome igual ao canal →
bateria = kit → "Ministro" = voz principal → tipo com canal único; ambíguo =
nada). Sugestão não é gravada; "Nenhum" grava 0 (escolha explícita).

**Barra:** uma faixa só, à esquerda, na ordem de uso — `[Eu: … ▾] [Equalizar | ✨] [🛡 Proteção]`, tudo com `_kCtlHeight` 36 / cantos de pílula. Botão duplo (`_SplitModeButton`): Equalizar à esquerda, Auto-Mix contínuo acoplado. "Desligar equalização" fica no ⋮ do topo (raro e perigoso de tocar sem querer).

**Detecção de instrumento: nome antes do ícone** (`ChannelMapper`) — na X32
real a tabela de ícones errou quase tudo ("Bumbo" → vocal, "Bass" → hi-hat).

**Estilo fixo em Worship:** o seletor saiu da tela — entre estilos de igreja a
diferença é ~1–4 dB, quase só bateria. `kGenreDeltas` fica no código pra voltar
num menu se fizer falta; um gênero salvo antigo é ignorado.

Equalizar e Auto-Mix são exclusivos (`MixerClient.monitorActive`). Escritas
internas passam por `_internal()` pra não virarem trim.

## Auto-Mix Engine

Modelo de compensação (`lib/engine/auto_mix_engine.dart`):

    send(ch) = C + master + alvo(instrumento) + boost − medidor(ch)

Mantém o nível de cada canal **no fone** constante: se o músico toca mais alto
(medidor sobe), o send desce na mesma medida; se toca mais baixo, o send sobe.
`C` é semeado na ativação (preserva o balanço atual, sem pulo) e fica **fixo** por
padrão (`refFollowSeconds → ∞`) — uma subida uniforme de toda a banda é ducked, não
acompanhada. `master` é o "volume geral" do músico (desloca o monitor todo sem
mexer no balanço entre canais) — exposto na UI como a barra **"Volume geral"**
(`_MasterVolumeBar` no mixer, faixa `kMasterMinDb..kMasterMaxDb` = −12..+12 dB),
lembrado **por bus** (`AppSettings.masterDb(mixer, bus)`), pois cada bus é o
monitor de uma pessoa. É o controle pra ajustar o nível do fone **no app**, em vez
de estourar a caixinha física.

**Master × duck (não pode se cancelar):** o `master` **não** entra no cálculo do
duck da estrela — se entrasse, subir o master aumentaria o déficit da voz (que
está no teto) → aumentaria o duck na mesma medida → a banda voltava pra baixo e o
knob "não fazia nada" (bug real pego num log de sim: master 10 vs 0 dava sends
idênticos). O `master` é aplicado à parte, como `masterEff`: **abaixar sempre
abaixa; subir é limitado pelo headroom da estrela até o teto** (`sendCeilingDb`) —
quando a voz já está no teto (medidor baixo → engine já jogou no talo, comum no
sim), subir não tem pra onde ir (honesto: o send está no máximo físico), só
abaixar/recuperar funciona. Numa mesa com ganho quente a voz não vive no teto e o
lado de cima também anda. E a mudança é **instantânea** (`_appliedMasterEff` +
`dMaster` deslocam os sends dos canais ativos no tick, sem o slew lento) — knob é
ação do usuário, não drift. Canais em silêncio ficam congelados (não deslocam).

**Alvo por instrumento** vem de `lib/state/genre_presets.dart`: `kBaseProfile`
(balanço neutro relativo à voz, âncora 0 dB) + `kGenreDeltas` (tempero por estilo).
O estilo só nuança o balanço neutro — nunca o sobrescreve.

**Gate relativo:** um canal só participa se estiver dentro de `activeRangeDb`
(40 dB) do canal mais alto do tick, e nunca abaixo de `silenceFloorDb` (−65 dB
absoluto). Silêncio real congela o canal — o Auto-Mix segura o que já está no
monitor, nunca "abre" (des-muta) um canal puxado pra baixo. Cadência: tick de
`kCorrectionIntervalMs` (1000 ms); o medidor do engine é uma **RMS de ~6 s**
(`lib/mixer/meter_stream.dart`). A média é no **domínio de potência** (amplitude²),
não em dB — senão fontes picotadas (skank de reggae, batida de bateria) leem
15–20 dB abaixo do real e o engine duca de menos, deixando-as altas no fone. A
janela era de ~3 s; foi alargada porque num log real o engine perseguia a dinâmica
de *frase* (voz/teclado bombeando pra dentro e pra fora) — 6 s deixa só mudança
sustentada de nível disparar correção.

**Anti-pumping (slew assimétrico + zona morta):** a correção não deve caçar
dinâmica musical, só drift. O passo é **assimétrico**: ducar (fonte ficou alta) até
`maxStepDb` (2 dB/s), mas *boostar* (fonte ficou baixa) só até `maxBoostStepDb`
(0,75 dB/s) — reage a "ficou alto" mas não corre pra preencher pausa/fim de frase
(que voltaria a ducar no próximo ataque). A `deadbandDb` é **2 dB** (era 1): tolera
variação de frase sem mexer. Antes o slew era 4 dB/s simétrico e o mix inteiro
oscilava dezenas de dB tick-a-tick ("sobe e some toda hora").

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

**Âncora do seed (`seedAnchorRangeDb`, 20 dB):** ao semear, o `C` sai da **mediana**
de `medidor + baseline − alvo` sobre os canais ativos — mas só os que estão dentro
de `seedAnchorRangeDb` do canal mais alto entram (janela mais estreita que os 40 dB
do gate de participação). Num log real, 3 canais colados no piso de silêncio
(vazamento / mic mal-aberta) que passaram o gate largo puxaram a mediana **~22 dB pra
baixo** (`C=-68,8` em vez de ~−44), estrangulando o monitor inteiro (tudo baixo,
músico forçado a jogar a caixinha do fone no talo). Restringir a âncora aos canais que
realmente carregam o mix semeia o `C` onde a banda de fato está. A janela é relativa
ao mais alto (independe da escala do console) e nunca mais frouxa que o gate.

**Premissa de tuning — fones-only (IEM no Stage, headphone na Live).** Sem caminho
acústico do monitor de volta pro microfone não há microfonia, então o motor é
agressivo pra cravar cada instrumento no alvo do estilo ("jogar no talo"): em
`EngineParams`, teto `sendCeilingDb` +10 dB, boost até `maxBoostDb` 24 dB, slew de
duck `maxStepDb` 2 dB/s / de boost `maxBoostStepDb` 0,75 dB/s (ver Anti-pumping
acima — era 4 dB/s simétrico). A única proteção de boost que sobra é a **guarda
adaptativa**
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
