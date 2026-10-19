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
   (`max(0.008, min(3 × percentil 10, percentil 90 / 2))` do RMS da trilha — com a mediana, uma trilha quase
   toda falada não teria nenhum trecho detectado) é fala. Juntar falas separadas por menos de 0,8 s; descartar
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

# Fase 2 — detectar a reunião

O Bkdict percebe que uma chamada começou e oferece gravar; quando ela acaba, oferece parar.

## Sinais (verificados a cada 3 s, só com "Detectar reuniões" ligado em Ajustes — padrão: ligado)

Uma chamada está acontecendo quando **um app de reunião está usando o microfone**:

| App | Mac (bundle id, por prefixo) | Windows (processo) |
|---|---|---|
| Zoom | `us.zoom` | `Zoom.exe` |
| Microsoft Teams | `com.microsoft.teams` | `ms-teams.exe`, `Teams.exe` (e o pacote `MSTeams_8wekyb3d8bbwe`) |
| Webex | `com.cisco.webex` | `CiscoCollabHost.exe`, `webexmta.exe` |
| FaceTime | `com.apple.FaceTime` | — |
| Slack (huddle) | `com.tinyspeck.slackmacgap` | `slack.exe` |
| Discord | `com.hnc.Discord` | `Discord.exe` |
| Navegador | Chrome, Safari, Arc, Edge, Firefox, Brave | `chrome.exe`, `msedge.exe`, `firefox.exe`, `brave.exe`, `arc.exe` |

- **Quem usa o microfone**: Mac — objetos de processo do Core Audio (`kAudioHardwarePropertyProcessObjectList`,
  `kAudioProcessPropertyIsRunningInput`, `kAudioProcessPropertyBundleID`; macOS 14.2+). Windows — o registro do
  Gerenciador de Acesso a Recursos (`HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\
  ConsentStore\microphone`, chaves `NonPackaged\*` e pacotes; em uso quando `LastUsedTimeStop` é 0).
  O próprio Bkdict nunca conta.
- **Navegador** só conta se alguma janela dele tiver no título `Meet`, `meet.google.com`, `Microsoft Teams`,
  `Teams`, `Zoom`, `Whereby` ou `Jitsi` (Mac: títulos das janelas pela Acessibilidade; Windows: títulos das janelas
  do processo). O nome mostrado é o do serviço (`Google Meet`, `Microsoft Teams`, `Zoom`…); `Meet` é testado
  por último, porque títulos do Zoom e do Teams costumam ter "Meeting". No Mac, se nenhum título
  puder ser lido (o Chrome só expõe as janelas à Acessibilidade quando um app assistivo pede), o navegador usando o
  microfone já conta, com o nome do navegador (`Reunião no Chrome`).
- A chamada **acabou** quando o app deixa de usar o microfone por 8 s seguidos.

## O que a pessoa vê

- **Começou e não está gravando**: a barra (fora do ditado) vira um convite por 20 s:
  `● Reunião no Zoom   [Gravar]  ×` — embaixo 360×40; nas laterais em pé 52×112 (ícone, botão gravar, ×; o texto
  como dica). "Gravar" começa a gravação com o título `Zoom · 18/10, 14:05`. "×" ou o tempo esgotado dispensam o
  convite **para esta chamada** (uma nova chamada convida de novo).
- **Acabou e está gravando**: convite `A chamada no Zoom acabou   [Parar e resumir]  ×` (mesmos tamanhos), por 30 s.
  "×" continua gravando. Gravações iniciadas à mão também recebem o convite quando a chamada que estava ativa acaba.
- Ajustes: linha "Detectar reuniões" — "Oferece gravar quando uma chamada começa no Zoom, Teams, Meet e outros".

# Fase 3 — quem é quem do lado de lá

A trilha **Eles** é separada por voz (`Pessoa 1`, `Pessoa 2`…), e a pessoa dá nome a cada voz.

## Separador de vozes

[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) v1.13.8, programa `sherpa-onnx-offline-speaker-diarization`,
instalado como as outras dependências (download na primeira reunião que precisar, verificado por SHA-256, em
`<suporte>/diarization/`):

| Peça | Arquivo |
|---|---|
| Programa, Mac | `v1.13.8/sherpa-onnx-v1.13.8-osx-universal2-shared-no-tts.tar.bz2` (39 MB) |
| Programa, Windows | `v1.13.8/sherpa-onnx-v1.13.8-win-x64-shared-MT-Release-no-tts.tar.bz2` (23 MB; `tar.exe` do Windows) |
| Segmentação | `speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2` → `model.onnx` (o completo, não o int8) |
| Voz | `speaker-recongition-models/3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx` (arquivo solto) |

(URLs em `https://github.com/k2-fsa/sherpa-onnx/releases/download/<pasta>/<arquivo>`.)

SHA-256: Mac `636b439c75031d892636dfdd2000a0233e4a30a08b030697e91f8aa389431b83`; Windows
`4b0a94f7b5c606b1b64a19a831c2127559e4b3d34e195465ebc7be73d9ed4783`; segmentação
`24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488`; voz
`357a834f702b80161e5b981182c038e18553c1f2ca752ed6cec2052365d4129b`. Os pacotes trazem tudo numa pasta
`sherpa-onnx-v1.13.8-…/` com o programa em `bin/` (no Windows, `bin/` já tem as DLLs ao lado do `.exe`).

Execução sobre `system.wav`, depois da transcrição, só se a reunião tem trechos **Eles**:

```
sherpa-onnx-offline-speaker-diarization --clustering.cluster-threshold=0.4 \
  --segmentation.pyannote-model=<model.onnx> --embedding.model=<campplus.onnx> system.wav
```

A saída tem linhas `0.031 -- 5.043 speaker_00`. Cada trecho **Eles** fica com a voz que mais se sobrepõe a ele no
tempo; trechos sem sobreposição ficam sem voz. As vozes são renumeradas pela ordem em que aparecem (0, 1, 2…).
Limiar 0,4: com gente de verdade separa bem; com vozes parecidas às vezes divide uma pessoa em duas — o que se
resolve juntando na tela (o contrário, desfazer uma mistura, não teria como).

Estado novo entre `transcribing` e `summarizing`: `separating` (`Separando as vozes`). Falha do separador não falha a
reunião: segue sem vozes, com `Eles` como antes.

## Dados

- `segments[].speaker`: número da voz (só em trechos `them`), ou ausente.
- `speakers`: lista de nomes por número de voz; `""` = nome padrão `Pessoa N` (N = número + 1).

## O que a pessoa vê

- Transcrição: os balões dos outros mostram o nome da voz (`Pessoa 1` ou o nome dado) no lugar de `Eles`, cada voz
  com uma cor discreta própria (tons neutros, não o Bordô, que é de "Você").
- Acima da conversa, o painel **Vozes**: um item por voz com ▶ (toca até 6 s da fala mais longa daquela voz, tirados
  de `system.wav`), o nome editável (salva ao sair do campo / Enter) e **Juntar com…** (menu com as outras vozes; os
  trechos passam para a escolhida e a voz some, renumerando as que vêm depois).
- Clique direito num balão dos outros: **Esta fala é de…** com cada voz e **Nova voz** — muda só aquele trecho
  (para quando o separador erra uma fala, e não uma voz inteira).
- Depois de dar nomes, juntar ou mudar falas, aparece **Refazer o resumo com os nomes**.
- O resumo usa os nomes: a transcrição enviada à IA traz `[mm:ss] Você: …` e `[mm:ss] <nome ou Pessoa N>: …`;
  a instrução passa a dizer que "Você" é quem gravou e que os outros nomes (ou `Pessoa N`) são participantes, e as
  tarefas começam com `Você:` ou com o nome de quem vai fazer (`Participantes:` quando não dá para saber).
  "Copiar transcrição" usa os mesmos rótulos.

## Fora da fase 3

Nomes automáticos pelo Zoom/Meet: exigem ler a interface de cada app de chamada durante a reunião (no navegador, o
Chrome só expõe a página a apps assistivos com uma extensão), e não dá para acertar sem chamadas reais para testar.
Fica para quando houver como testar; os convidados do calendário (fase 4) vão sugerir nomes.

## Fora das fases 1, 2 e 3

Calendário, perguntar sobre as reuniões, tarefas como ações (fase 4).
