# Stems de teste do simulador

Faixas por instrumento usadas pelo `x32_sim.dart --web` para tocar música real
e testar o Auto-Mix (cada canal = um stem; ganho = entrada × send do app).

## Fonte e licença

Excertos multitrack da **Cambridge-MT "Mixing Secrets" Free Multitrack Download
Library** (https://cambridge-mt.com/ms/mtk/), disponibilizados **gratuitamente
para prática e uso educacional de mixagem**. Os direitos são dos artistas.

> Uso interno para desenvolvimento/teste deste app. **Não redistribuir** fora
> deste contexto nem usar comercialmente. Se este repositório se tornar público,
> estes arquivos devem ser removidos (e migrados para um script de download).

Músicas:
- **Big Stone Culture — Fragile Thoughts** (Reggae)
- **Angels in Amplifiers — I'm Alright** (Blues Rock)
- **The Long Wait — Dark Horses** (Indie Rock)

## Como foram gerados

Baixados os "Excerpt Stems", mapeados aos canais da mesa do simulador, cortados
no mesmo tamanho (loop travado), normalizados (`loudnorm`) e convertidos para
OGG mono. O `manifest.json` (canal → arquivo, por música) é servido em
`/manifest`; os áudios em `/audio/<song>/chNN.ogg`.
