# Dynamic Island para Mac

Uma Dynamic Island nativa no notch do MacBook que mantém o **usage do Cursor** no canto do olho enquanto você programa — com Spotify, Screenshot Clipboard e **This Mac** (CPU / RAM / energia) como módulos extras.

[English (primary)](README.md)

---

## Motivação

Como desenvolvedor, eu vivo dentro do editor. O usage incluso do Cursor (e a velocidade com que ele some) importa todo dia — mas o dashboard fica em outra aba, outro contexto, outra quebra de fluxo.

Eu queria esse sinal onde o olhar já passa: o **notch do MacBook**. Uma pílula de relance que responde “quanto do plano eu já usei?” sem abrir Settings ou a página de billing.

Esse é o núcleo do projeto: **consciência no dia a dia do desenvolvedor**. O Spotify entrou depois, como módulo extra — útil quando a música já está tocando, mas não é o motivo da island existir. O Screenshot Clipboard entrou no mesmo espírito: conveniência terciária para capturas recentes sem sair do notch. **System** segue a mesma ideia para a máquina — um relance de CPU, RAM e energia no notch.

Este repositório é **open source**. Use, faça fork, melhore.

---

## O que faz

### Cursor (principal)

- Mostra o usage incluso de **Cursor Models** e **Other Models** (a mesma ideia de dois pools do dashboard)
- Modo compacto: um único percentual (o maior dos dois), com cor perto do limite
- Modo expandido: dias até o próximo reset de usage (`Resets today` / `N day(s) until reset`) ficam **acima** das barras de consumo, depois as barras e textos no estilo da UI web
- Login via WebView embutida; sessão no Keychain
- Pulse suave ao cruzar 90% / 100%

### Spotify (secundário)

- Now playing (capa, título, artista) com o app desktop do Spotify aberto
- Play / pause / anterior / próxima via AppleScript
- No compacto, prioriza a faixa quando a música está tocando

### Screenshot Clipboard (terciário)

- Captura screenshots do sistema (`⇧⌘3/4/5`) num histórico no notch das **3 últimas**
- Abrir o módulo Screenshots (ícone de câmera) já mostra essas **3 últimas** do histórico local — não uma faixa vazia até a próxima captura
- Expande por alguns segundos na captura; reabra pelo switcher de módulos
- Clique na preview para copiar; arraste para outros apps (arquivo + imagem); **X** no hover para remover
- **+** colapsa a island e abre a UI nativa de screenshot (`⇧⌘5`)
- Funciona com Save to em **File** ou **Clipboard** — destino clipboard é suportado de ponta a ponta
- **Accessibility** opcional melhora a detecção de atalhos e habilita o **+**; detecção via arquivo / prefs do sistema continua sem ela

### System (This Mac)

- Aba expandida com título **This Mac**: **CPU**, **RAM** e **Energy** ao vivo
- Cada valor tem um rótulo curto de unidade embaixo: CPU **Percent used**, RAM **Gigabytes used** (`usado/total GB`), Energy **Avg app watts** (média móvel da energia dos apps em execução — não é bateria)
- O badge compacto mostra o % de CPU; o ícone do switcher é o glifo de CPU (`cpu.fill`)
- Amostragem local (host statistics + contadores de energia por app) — nada sai da máquina

---

## Funcionalidades

- Island em SwiftUI colada no display **built-in** com notch (monitores externos ignorados)
- Morph compacto ↔ expandido com spring
- Troca de módulo (Cursor / Spotify / Screenshots / System) no expandido
- App de menu bar (sem ícone no Dock): sign in/out, refresh, launch at login, quit
- Abrir no login via `SMAppService`

---

## Requisitos

- macOS 14+
- MacBook com notch (posicionamento no display interno)
- Conta Cursor (para o usage)
- App desktop do Spotify (só se quiser os controles de música)
- Permissão de Automação para o Spotify quando o sistema pedir
- Permissão de Accessibility (opcional) para o UX completo do Screenshot Clipboard (`+` e armamento de atalhos)

---

## Build e execução

```bash
./Scripts/package-app.sh
open build/DynamicIsland.app
```

Alternativas:

- Abrir `DynamicIsland.xcodeproj` no Xcode e rodar, ou
- `swift build -c release` e empacotar com o script acima

No primeiro uso: **Sign in to Cursor** pela island ou pelo ícone da menu bar. Para o Spotify, libere **Automation** quando o macOS pedir. Para o botão **+** do Screenshot Clipboard e a melhor captura via clipboard, libere **Accessibility** quando pedido (ou pelo hint na menu bar).

---

## Permissões e privacidade

| Permissão | Por quê |
|---|---|
| Keychain | Guarda o cookie de sessão do Cursor |
| Automation | Controla playback / metadata do Spotify |
| Rede | Chama a API de usage do dashboard do Cursor |
| Accessibility | Detecta atalhos de screenshot e dispara `⇧⌘5` pelo botão **+** (opcional) |

**Avisos:** o usage do Cursor vem de um endpoint não documentado do dashboard (`/api/usage-summary`) com o cookie de sessão. O Cursor pode mudar ou quebrar isso a qualquer momento. Trate como ferramenta pessoal / experimental — use por sua conta e risco. Este app não envia telemetria própria além do que as APIs do Cursor recebem ao buscar o usage. As previews de screenshot ficam só no disco local (últimas 3) em Application Support e voltam ao abrir a aba Screenshots; os arquivos originais no Desktop não são movidos nem apagados. CPU, RAM e energia dos apps ficam no dispositivo. Energia é a média em tempo real da potência atribuída aos apps em execução, não a carga da bateria.

---

## Estrutura do projeto

```
Sources/DynamicIsland/
  App/           # Entrada do app, menu bar, bootstrap
  Island/        # Painel do notch, morph, views
  Features/      # Usage do Cursor + Spotify + Screenshot Clipboard + System (This Mac)
  Auth/          # Login via WebView
  Support/       # Geometria, Keychain, motion, logos
Scripts/         # package-app.sh
Resources/       # Info.plist
```

---

## Contribuindo

Issues e pull requests são bem-vindos — especialmente resiliência da API do Cursor, geometria do notch em mais máquinas e polish de UI.

---

## Licença

[MIT](LICENSE)
