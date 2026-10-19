<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Ícone do BKDict">
</p>

<h1 align="center">BKDict</h1>

<p align="center">
  Ditado por voz para macOS e Windows, da BKDG. Segure uma tecla, fale e solte: o texto aparece onde o cursor estiver, em qualquer app.<br>
  A transcrição e a IA rodam <b>no seu computador</b> (nada sai da máquina) ou na <b>sua conta</b>, com a sua chave de API.
</p>

<p align="center">
  <a href="https://github.com/cadu-web/bkdict/releases/latest/download/BKDict.dmg"><img src="https://img.shields.io/badge/Baixar%20para%20Mac-macOS%2014%2B%20%C2%B7%20Intel%20e%20Apple%20Silicon-611E2C?style=for-the-badge&logo=apple&logoColor=F1ECE2&labelColor=0A0A0A" alt="Baixar o BKDict para Mac" height="44"></a>
  &nbsp;
  <a href="https://github.com/cadu-web/bkdict/releases/latest/download/BKDict-windows.zip"><img src="https://img.shields.io/badge/Baixar%20para%20Windows-Windows%2010%20e%2011-611E2C?style=for-the-badge&logo=windows&logoColor=F1ECE2&labelColor=0A0A0A" alt="Baixar o BKDict para Windows" height="44"></a>
</p>

<p align="center">
  <sub>Sem cadastro · sem Terminal · <a href="#instalar-no-mac">como instalar no Mac</a> · <a href="#instalar-no-windows">no Windows</a></sub>
</p>

<p align="center">
  <img src="docs/images/transforms.png" alt="Tela de Transforms do BKDict" width="820">
</p>

---

## O que é

O BKDict transcreve o que você fala em qualquer app (Slack, email, Notion, navegador, editor de código), remove vícios de fala, corrige a pontuação e cola o resultado onde o cursor estiver. O clipboard é preservado.

Você escolhe onde cada parte roda:

- **No seu computador:** transcrição com [whisper.cpp](https://github.com/ggml-org/whisper.cpp) e IA com [Ollama](https://ollama.com), que o app instala sozinho. Privado, sem custo e sem Terminal.
- **Na sua conta:** chave de API da OpenAI, Anthropic (Claude), Groq, Google Gemini ou xAI (Grok).

## Recursos

- **Segure e fale:** segure `Fn` (ou o atalho que você definir), fale e solte. O texto é colado no app em foco.
- **Mãos livres:** dois toques no `Fn` (ou `Fn + Espaço`) começam a gravar sem segurar a tecla; um toque no `Fn` para e cola.
- **Barra de ditado:** fica no pé da tela ou numa lateral; passe o mouse para ditar ou gravar uma reunião com um clique.
- **Cola só em campo de texto:** fora de um campo, o ditado não se perde: aparece num card com o botão de copiar.
- **Modo comando:** selecione um texto, segure `Fn + ⌃` e diga a instrução ("traduz para inglês", "deixa mais formal").
- **Transforms:** reescritas acionadas por atalho (formal, resumo, tópicos, email, tradução). Crie as suas, com sugestões geradas pela IA, ou aplique uma automaticamente em todo ditado.
- **Atalhos:** até 2 por ação. Pode ser uma tecla F, uma combinação, um modificador sozinho (Shift direito, Fn) ou um botão extra do mouse.
- **Dicionário e correções:** nomes, siglas e termos técnicos que a transcrição precisa escrever certo.
- **Snippets:** uma frase-gatilho ("meu email") insere um texto fixo.
- **Ajuste com IA:** remove "é…", "tipo" e repetições, e corrige a pontuação, sem responder o que você perguntou.
- **Microfone:** escolha qual usar; no automático, com fone Bluetooth o BKDict grava pelo microfone do computador, e a música não pausa.
- **Histórico** de ditados, estatísticas e tema claro, escuro ou do sistema.
- **Reuniões:** grava o seu microfone e o áudio do computador, transcreve separando **Você** de cada participante
  (o separador de vozes local dá `Pessoa 1`, `Pessoa 2`…, e você ouve e dá nome) e resume em decisões, tarefas e
  pontos em aberto. Percebe quando uma chamada começa (Zoom, Teams, Meet, Webex, FaceTime, Slack, Discord) e oferece
  gravar, com a transcrição ao vivo na barra; responde perguntas sobre as reuniões; marca tarefas como feitas e as
  copia, envia por e-mail ou cria Lembretes. Tudo no seu computador; detalhes em [`docs/reunioes.md`](docs/reunioes.md).
  No Mac, o áudio dos outros exige macOS 14.2+ e a permissão "Gravação de Áudio do Sistema".

## Modelos

<p align="center">
  <img src="docs/images/models.png" alt="Escolha de modelos do BKDict" width="820">
</p>

Na aba **Modelos**, cada parte responde a uma pergunta: *no meu computador* ou *na minha conta (chave de API)*?

| | No seu computador (sem custo) | Na sua conta (chave de API) |
|---|---|---|
| **Transcrição** | Whisper: Base, Small, Medium, Large v3 e Large v3 Turbo, baixados dentro do app | OpenAI (`gpt-4o-transcribe`…) ou Groq (`whisper-large-v3-turbo`…) |
| **IA** (ajuste, comando, transforms) | Ollama (o app instala): Qwen 2.5, Llama 3.x, Mistral, Gemma 2, Phi-3… | OpenAI, Anthropic, Groq, Gemini ou xAI |

No macOS, as chaves de API ficam no **Keychain**; no Windows, no **Gerenciador de Credenciais**. Nunca em arquivo.

## Atalhos

<p align="center">
  <img src="docs/images/settings.png" alt="Ajustes do BKDict" width="820">
</p>

| Ação | Mac | Windows |
|---|---|---|
| Ditar (segurar) | `Fn` | `Ctrl + Win` |
| Mãos livres | Dois toques no `Fn`, ou `Fn + Espaço` | Dois toques no `Ctrl + Win`, ou `Ctrl + Win + Espaço` |
| Modo comando (segurar) | `Fn + ⌃` | `Ctrl + Win + Alt` |
| Transform 1…9 | `Fn + 1…9` (ou o atalho de cada transform) | `Ctrl + Win + 1…9` |
| Colar / copiar a última transcrição | `⌃⌘V` / `⌃⌘C` | `Win + Alt + V` / `Win + Alt + C` |
| Cancelar | `Esc` | `Esc` |

O Windows não enxerga a tecla `Fn`, então `Ctrl + Win` faz o papel dela. Todos podem ser trocados em **Ajustes → Atalhos**.

## Instalar no Mac

<table>
  <tr>
    <td align="center" width="33%"><h3>1</h3><b>Baixe</b></td>
    <td align="center" width="33%"><h3>2</h3><b>Arraste para Aplicativos</b></td>
    <td align="center" width="33%"><h3>3</h3><b>Abra e siga a tela de boas-vindas</b></td>
  </tr>
  <tr>
    <td valign="top">Clique em <a href="https://github.com/cadu-web/bkdict/releases/latest/download/BKDict.dmg"><b>Baixar para Mac</b></a>. Vem sempre a versão mais recente.</td>
    <td valign="top">Abra o <code>BKDict.dmg</code> e arraste o ícone do BKDict para a pasta <b>Aplicativos</b>.</td>
    <td valign="top">Abra o BKDict. Clique em <b>Permitir</b> no microfone e em <b>Abrir Ajustes</b> na Acessibilidade (ative o BKDict na lista). A transcrição baixa sozinha.</td>
  </tr>
</table>

<p align="center">
  <img src="docs/images/onboarding.png" alt="Tela de boas-vindas do BKDict" width="560">
</p>

Pronto: **segure `Fn`, fale e solte.** O texto aparece onde o cursor estiver.

Requisitos: macOS 14 ou superior, Intel ou Apple Silicon. No primeiro uso, o app instala sozinho o **whisper** (transcrição, cerca de 5 MB) e o **Ollama** (IA local, cerca de 175 MB) em `~/Library/Application Support/Bkdict`, sem Terminal nem Homebrew.

<details>
<summary><b>Problemas na instalação?</b></summary>

- **O macOS não deixa abrir na primeira vez:** o BKDict ainda não é assinado com certificado da Apple. Vá em Ajustes do Sistema → Privacidade e Segurança → **Abrir Mesmo Assim**, ou rode `xattr -dr com.apple.quarantine /Applications/BKDict.app`.
- **A tecla `Fn` abre os emojis ou o ditado do macOS:** em Ajustes do Sistema → Teclado, deixe **"Ao pressionar 🌐"** como **Não fazer nada**.
- **Não cola o texto:** confira se o BKDict está ativado em Ajustes do Sistema → Privacidade e Segurança → **Acessibilidade**.
- **O botão de baixar dá 404:** enquanto o repositório for privado, os downloads só funcionam para quem tem acesso a ele e está logado no GitHub.
- **Versões anteriores:** na [página de releases](https://github.com/cadu-web/bkdict/releases).

</details>

## Instalar no Windows

<table>
  <tr>
    <td align="center" width="33%"><h3>1</h3><b>Baixe</b></td>
    <td align="center" width="33%"><h3>2</h3><b>Extraia</b></td>
    <td align="center" width="33%"><h3>3</h3><b>Abra e siga a tela de boas-vindas</b></td>
  </tr>
  <tr>
    <td valign="top">Clique em <a href="https://github.com/cadu-web/bkdict/releases/latest/download/BKDict-windows.zip"><b>Baixar para Windows</b></a>. Vem sempre a versão mais recente, com o .NET embutido.</td>
    <td valign="top">Extraia o <code>BKDict-windows.zip</code> numa pasta sua (por exemplo, <code>Documentos</code>).</td>
    <td valign="top">Abra o <code>BKDict.exe</code>. A tela de boas-vindas confere o microfone e baixa a transcrição sozinha.</td>
  </tr>
</table>

Pronto: **segure `Ctrl + Win`, fale e solte.** Requisitos: Windows 10 ou 11 (x64). Na primeira abertura, o Windows pode mostrar o aviso do SmartScreen: clique em **Mais informações → Executar assim mesmo**. Para compilar do código e os detalhes da versão Windows, veja o [README do Windows](windows/README.md).

## Como funciona

```
tecla segurada ─▶ AVCaptureSession (16 kHz) ─▶ whisper-server local / API de transcrição
                                                     │
                     colar no app em foco ◀─ dicionário, snippets ◀─ ajuste / transform com IA
```

- App nativo em **Swift + SwiftUI**, sem Electron. Os atalhos usam um `CGEventTap`, e o texto entra via clipboard + `⌘V`, com o clipboard restaurado logo depois.
- A transcrição local roda o `whisper-server` do whisper.cpp em segundo plano, com o modelo carregado para responder rápido. A IA local roda o `ollama serve`. O app inicia os dois e encerra ao sair; um Ollama que já estava rodando antes fica como estava.
- Histórico, dicionário e transforms ficam em `~/Library/Application Support/Bkdict`.

## Identidade visual

O app segue o design system da BKDG:

- **Cores:** Tinta `#0A0A0A`, Osso `#F1ECE2` e Bordô `#611E2C`. No modo escuro, o acento é o Bordô claro `#B33751`, porque o Bordô cheio some sobre Tinta (1,63:1).
- **Fontes:** Zilla Slab nos títulos, IBM Plex Sans no texto e IBM Plex Mono nos rótulos em caixa-alta. Ficam em `Resources/Fonts`, com as licenças OFL, e entram no app pelo `ATSApplicationFontsPath` do `Info.plist`.
- **Formas:** cantos de no máximo 4pt, superfícies chapadas, sem gradiente, brilho ou sombra.
- **Símbolo:** o Observador da BKDG, com três ondas de voz. O cão vem do vetor oficial (`brand-mark.svg`), sem redesenho. No código, ele é a forma `BrandMark` em `Sources/Bkdict/UI/Theme.swift`; os tokens de cor e fonte estão no mesmo arquivo.

| Arquivo | O que é |
|---|---|
| `Resources/Icons/app-icon.svg` | Fonte do ícone do macOS |
| `Resources/Icons/app-icon-windows.svg` | Fonte do ícone do Windows (sem a margem que o macOS aplica) |
| `Resources/Icons/menubar-icon.svg` | Fonte do ícone da barra de menus (template) |
| `Resources/AppIcon-1024.png`, `AppIcon-windows-1024.png`, `MenuBarIcon*.png` | Gerados a partir dos SVGs |
| `Resources/dmg-background.tiff` | Fundo do instalador `.dmg` |

Para regenerar depois de mudar um SVG ou o fundo do `.dmg`:

```sh
npm i --no-save sharp && node scripts/gen-icons.mjs
swift scripts/gen-dmg-background.swift
```

## Desenvolvimento

Requisitos: Xcode 16+ (Swift 5.10+).

```sh
swift build          # compila
./build.sh           # gera dist/BKDict.app
./build.sh --install # copia para /Applications
./build.sh --release # app universal (Intel + Apple Silicon) em dist/BKDict-x.y.z.zip e .dmg (requer: brew install create-dmg)
```

O identificador `co.bkdg.bkdict` é fixo para o macOS manter as permissões de Microfone e Acessibilidade entre builds.

### Publicar uma versão

```sh
# 1. Suba CFBundleShortVersionString (ex.: 0.2.0) e CFBundleVersion (inteiro, sempre maior) em Resources/Info.plist
# 2. Publique (requer create-dmg, .NET 10 SDK e o gh logado na cadu-web)
scripts/release.sh "O que mudou nesta versão"
```

O script gera o DMG e o ZIP do Mac, o ZIP do Windows (com o .NET embutido), o `appcast.xml` assinado, e cria a release `vX.Y.Z` em `cadu-web/bkdict`. O DMG e o ZIP do Windows sobem com nome fixo (`BKDict.dmg`, `BKDict-windows.zip`), para os botões de download do topo sempre baixarem a última versão.

**Atualização automática:**

- **No Mac**, o [Sparkle](https://sparkle-project.org) consulta o `appcast.xml` da release mais recente. Ele instala a versão nova quando a pessoa aceita; dá também para procurar manualmente em **Procurar atualizações…**, no menu do app.
- **No Windows**, o app consulta a release mais recente ao abrir e, se houver versão nova, avisa na bandeja com o link para baixar.

Cada atualização do Mac é assinada com uma chave EdDSA. A pública está no `Info.plist` (`SUPublicEDKey`); a privada fica no Keychain de quem publica, na conta `bkdict`. **Sem a chave privada, nenhum app instalado aceita uma atualização nova.** Faça backup dela com `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account bkdict -x bkdict-sparkle.key` e guarde num cofre de senhas, nunca no repositório.

Enquanto o repositório for privado, os downloads do whisper, do appcast e das versões dão 404 para quem não está logado. A atualização automática e a instalação do whisper no Mac passam a funcionar sozinhas quando ele ficar público.

### Dependências instaladas no primeiro uso

O app baixa as dependências de endereços fixos, definidos em `Sources/Bkdict/Dependency.swift`:

| Dependência | Origem |
|---|---|
| Ollama | Release oficial mais recente: `github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz` |
| whisper | Compilado pela gente, porque o whisper.cpp não publica binário para macOS: release `whisper-v1.9.5` de `cadu-web/bkdict` (pré-lançamento), arquivo `whisper-server-macos.tgz`, conferido por SHA-256 |

Para gerar o whisper (estático, Intel + Apple Silicon, com Metal) e publicar a release:

```sh
brew install cmake
scripts/build-whisper.sh   # gera dist/whisper-server-macos.tgz
gh release create whisper-v1.9.5 dist/whisper-server-macos.tgz -R cadu-web/bkdict --prerelease
```

Ao trocar a versão do whisper.cpp, mude `WHISPER_VERSION` no script, publique numa release nova e atualize a URL e o SHA-256 (o script imprime) em `Dependency.swift`. A release do whisper é pré-lançamento para não virar a "mais recente" que a atualização automática consulta.

## Licença

Copyright (c) 2026 BKDG. Todos os direitos reservados. O BKDict é software proprietário: uso, cópia, modificação e distribuição só com autorização da BKDG. Os termos estão em [`LICENSE`](LICENSE).

Avisos de componentes de terceiros também estão no `LICENSE`. As fontes IBM Plex e Zilla Slab são distribuídas sob a SIL Open Font License (`Resources/Fonts/OFL-*.txt`).
