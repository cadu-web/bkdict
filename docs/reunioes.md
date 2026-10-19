# Reuniões — fase 1

Gravar uma reunião, transcrever separando **Você** (microfone) de **Eles** (áudio do sistema) e gerar um resumo.
Mac e Windows se comportam igual; este documento é o contrato entre os dois.

## O que a pessoa vê

- **Gravar reunião**: botão no topo da tela **Reuniões**, item no menu do app (barra de menus / bandeja) e no clique
  direito da barra de ditado. Enquanto grava, o mesmo lugar vira **Parar gravação** e a tela mostra o tempo.
- **Barra de ditado durante a gravação** (quando não está ditando): em vez da barrinha parada, uma pílula
  `● 12:34 ■` (ponto em `#B33751`, tempo em IBM Plex Mono, botão parar). Embaixo: 112×28. Nas laterais, em pé:
  32×84 (ponto, tempo em duas linhas `12` / `34`, botão). Ditar continua funcionando durante a reunião.
- **Tela Reuniões** (item novo na barra lateral, entre Histórico e Transforms):
  - lista: título (`Reunião de 18/10, 14:05`), duração, estado (`Gravando`, `Transcrevendo 40%`, `Resumindo`,
    `Pronta`, `Só o seu microfone`, `Falhou: <motivo>`);
  - detalhe: **Resumo** (Markdown simples: títulos `##`, listas `-`) e **Transcrição**, uma linha por trecho:
    `[12:04] Você: …` / `[12:09] Eles: …`; botões **Copiar resumo**, **Copiar transcrição**, **Apagar**
    (confirma, apaga a pasta inteira) e **Refazer resumo**.
- **Sem permissão de áudio do sistema** (ou Mac antes do 14.2): grava só o microfone e a reunião mostra
  `Só o seu microfone — libere a gravação do áudio do sistema para captar os outros`.

## Gravação

Duas trilhas, gravadas direto em arquivo enquanto a reunião acontece (uma reunião de 1 h não cabe em memória):

| Trilha | Fonte | Arquivo |
|---|---|---|
| Você | microfone escolhido em Ajustes (mesma regra do automático) | `mic.wav` |
| Eles | áudio do sistema, menos o próprio Bkdict | `system.wav` |

Formato: WAV PCM 16 bits, mono, 16 kHz (o que o Whisper usa). Converter o que vier (48 kHz estéreo float etc.).

- **Mac**: microfone com uma `AVCaptureSession` própria; sistema com **Core Audio process tap**
  (`CATapDescription` global excluindo o processo do Bkdict + dispositivo agregado privado + IOProc),
  macOS 14.2+. Requer `NSAudioCaptureUsageDescription` no `Info.plist`.
- **Windows**: microfone com `WaveInEvent` no dispositivo escolhido; sistema com `WasapiLoopbackCapture`
  (NAudio.Wasapi) do dispositivo de saída padrão. Reamostrar para 16 kHz mono.

Pasta da reunião: `<suporte>/meetings/<id>/` com `mic.wav`, `system.wav` e `meeting.json`
(`<suporte>` = `~/Library/Application Support/Bkdict` no Mac, `%LOCALAPPDATA%\Bkdict` no Windows — áudio é grande
e não deve sincronizar com o perfil). `<id>` = data e hora `2026-10-18_14-05-12`.

```json
{
  "id": "2026-10-18_14-05-12",
  "title": "Reunião de 18/10, 14:05",
  "startedAt": "2026-10-18T14:05:12-03:00",
  "duration": 2712.4,
  "systemAudio": true,
  "status": "ready",            // recording | transcribing | summarizing | ready | failed
  "progress": 1.0,
  "error": null,
  "segments": [ { "source": "me", "start": 12.4, "end": 15.9, "text": "…" } ],   // source: me | them
  "summary": "## Resumo\n…"
}
```

## Transcrição

1. **Trechos com fala (VAD por energia)**, por trilha: janelas de 30 ms; RMS acima de um limiar adaptativo
   (`max(0.008, 3 × mediana do RMS da trilha)`) é fala. Juntar falas separadas por menos de 0,8 s; descartar
   trechos com menos de 0,4 s; cortar trechos maiores que 30 s no silêncio mais próximo (ou em 30 s). Margem de
   0,2 s antes e depois.
2. **Transcrever cada trecho** com o motor escolhido (whisper local ou API), com o vocabulário do Dicionário como
   dica, na ordem do tempo, alternando as duas trilhas. Progresso = trechos feitos / total.
3. **Eco**: sem fone, o microfone capta os outros pelo alto-falante. Um trecho **Você** que se sobrepõe no tempo a
   um trecho **Eles** e tem ≥ 60% das palavras iguais (sem acento, minúsculas) é descartado.
4. Ordenar por início; aplicar as Correções do Dicionário; trechos vazios saem.

## Resumo

Pela IA escolhida em Modelos (a mesma do ajuste/transforms). Texto de entrada: a transcrição no formato
`[mm:ss] Você|Eles: texto`. Saída em Markdown, no idioma da reunião:

```
## Resumo
(3 a 6 frases)
## Decisões
- …
## Tarefas
- Quem: o quê (prazo, se dito)
## Pontos em aberto
- …
```

Seções sem conteúdo dizem `- Nenhuma.` A instrução proíbe inventar o que não foi dito. O modelo acima vai na
mensagem, depois da transcrição, para ser **preenchido**; a instrução define que "Você" é quem gravou, que linhas
"Eles" são dos outros (mesmo quando dizem "eu faço") e que cada tarefa começa com `Você:` ou `Participantes:`.
Testado com o Qwen 2.5 3B local: sem o modelo a preencher ele pula seções e dá as tarefas dos outros a "você".
Para reuniões, um modelo maior (Qwen 2.5 7B, ou um da nuvem) resume melhor. Transcrição longa
(> 8.000 caracteres): dividir em partes de até 8.000 caracteres em fronteira de linha, resumir cada parte em notas
(mesmas seções), e gerar o resumo final a partir das notas. Sem IA configurada: a reunião fica `ready` só com a
transcrição e o resumo diz como configurar.

## Fora da fase 1

Detectar a reunião sozinho, separar as vozes do lado de lá, nomes pelo Zoom/Meet, calendário, perguntar sobre as
reuniões.
