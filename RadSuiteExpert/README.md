# RadSuite Expert

Toolkit de produtividade para a IDE do Delphi 13, baseado na Open Tools API
(`ToolsAPI`). Inspirado no [GExperts](https://www.gexperts.org/) e no
[CnWizards](https://github.com/cnpack/cnwizards), reúne um conjunto de
ferramentas num único menu **RadSuite** da IDE.

## Estrutura

```
RadSuiteExpert/
├── RadSuiteExpertD13.dpk           Projeto de package (design-time only)
├── RadSuiteExpertD13.dproj         Ficheiro de projeto (MSBuild)
└── src/
    ├── RadSuite.IDE.Utils.pas          Helpers OTA partilhados (editor, projeto, ficheiros)
    ├── RadSuite.Expert.MainMenu.pas    Regista o menu "RadSuite" na IDE
    ├── RadSuite.Expert.Wizard.pas      TRadSuiteWizard (registo mínimo IOTAWizard)
    ├── RadSuite.Expert.AboutBox.pas    Entrada na About Box
    ├── RadSuite.Expert.Register.pas    initialization/finalization do package
    ├── UI/
    │   └── RadSuite.UI.Theme.pas       Tema visual partilhado (cores, cabeçalho das janelas)
    └── Tools/
        ├── RadSuite.Tools.GrepSearch.pas
        ├── RadSuite.Tools.UsesClauseManager.pas
        ├── RadSuite.Tools.ClassBrowser.pas
        ├── RadSuite.Tools.UnitDependencies.pas
        ├── RadSuite.Tools.CodeLibrarian.pas
        ├── RadSuite.Tools.AIAssistant.pas
        ├── RadSuite.Tools.PEInformation.pas
        ├── RadSuite.Tools.AsciiChart.pas
        └── RadSuite.Tools.CleanDirectories.pas
```

O package está marcado como `{$DESIGNONLY}` — só é carregado pela IDE, nunca
é distribuído com as aplicações compiladas. Todas as janelas são construídas
inteiramente por código (sem `.dfm`), para evitar problemas de recursos
binários entre versões do Delphi.

## Ferramentas incluídas

Acessíveis a partir do menu **RadSuite** da IDE:

| Ferramenta | O que faz |
|---|---|
| **Grep Search & Replace** | Procura (texto ou regex) em ficheiros abertos, no projeto ativo ou numa pasta; janela não-modal com resultados navegáveis (duplo-clique salta para a ocorrência); substituição em lote nos ficheiros marcados, com confirmação. |
| **Uses Clause Manager** | Lista as units das cláusulas `uses` (interface/implementation) da unit ativa; sinaliza como sugestão as que não aparecem em mais nenhum sítio do ficheiro (heurística textual, não é análise semântica do compilador); permite remover/ordenar e aplicar ao editor. |
| **Class Browser** | Árvore de classes → métodos/propriedades/campos da unit ativa, detetados por expressões regulares (não resolve tipos aninhados nem heranças de outras units); duplo-clique navega até à declaração. |
| **Unit Dependencies** | Lê as cláusulas `uses` de todas as units do projeto ativo e mostra, por unit, de que outras units do projeto depende e por quais é usada. |
| **Code Librarian** | Gestor de snippets de código por categorias, guardados em `%APPDATA%\RadSuite\CodeLibrary.txt`; insere o snippet selecionado no editor ativo. |
| **AI Assistant** | Painel de prompt com resposta da API Claude (Anthropic); pode incluir o código selecionado como contexto; insere ou substitui a seleção no editor com a resposta. Requer API key própria (ver secção abaixo). |
| **PE Information** | Inspetor de ficheiros PE (EXE/DLL/BPL): DOS/NT headers, secções, imports e exports, lidos diretamente do binário (32 e 64-bit). |
| **ASCII Chart** | Tabela de caracteres ASCII 0-255 (decimal/hex/carácter), com cópia para a clipboard. |
| **Clean Directories** | Varre a pasta do projeto (ou outra à escolha) por ficheiros temporários/intermédios do Delphi (`.dcu`, `.~*`, `.local`, `__history`, etc.) e permite apagar os selecionados, com confirmação. |

### AI Assistant — privacidade e configuração

- A API key é guardada **apenas localmente**, em
  `%APPDATA%\RadSuite\ai-config.ini`, e nunca é incluída no repositório.
- Quando a ferramenta é usada, o texto do prompt (e o código selecionado, se
  a opção estiver marcada) é enviado para a API pública da Anthropic
  (`https://api.anthropic.com/v1/messages`). Nada é enviado automaticamente
  — só quando o utilizador clica em "Enviar".
- O modelo por omissão é `claude-sonnet-5`, configurável no botão
  "Configurar...".

## Compilar e instalar

> Estes passos assumem o Delphi 13 instalado no Windows. Este código foi
> escrito sem acesso a uma instalação do Delphi (ambiente de
> desenvolvimento em Linux), portanto **ainda não foi compilado nem testado
> na IDE real**. É provável que sejam necessários pequenos ajustes ao abrir
> pela primeira vez (ex.: a IDE pode pedir para atualizar a versão do
> projeto `.dproj`) — reportar quaisquer erros de compilação encontrados.

1. Abra `RadSuiteExpertD13.dproj` no Delphi 13.
2. Se a IDE pedir para atualizar a versão do projeto, aceite.
3. Compile o package (`Project > Build`).
4. Instale-o: `Component > Install Packages... > Add`, e selecione o
   `.bpl` gerado (normalmente em `Win32\Debug\RadSuiteExpertD13.bpl` ou
   `Win64\Debug\...`).
5. Reinicie a IDE. Deverá aparecer:
   - Uma entrada "RadSuite Expert" na About Box (`Help > About`).
   - Um menu **RadSuite** na barra de menus principal, com as 9 ferramentas.

## Limitações conhecidas (âmbito v1)

- **Uses Clause Manager**: a deteção de units "possivelmente não usadas" é
  uma heurística textual (procura o nome no resto do ficheiro), pode ter
  falsos positivos/negativos — a remoção é sempre manual/confirmada.
- **Class Browser**: analisa apenas a unit ativa no editor, via regex —
  não resolve tipos aninhados, genéricos complexos ou heranças fora da unit.
- **Unit Dependencies**: só considera as units do próprio projeto (lidas do
  disco), não resolve o search path completo nem units externas.
- **Grep Search & Replace**: janela não-modal simples, sem docking nativo
  na IDE.
- Nenhum destes ficheiros foi compilado/testado num Delphi real — ver nota
  acima.

## Próximos passos possíveis

- Testar e corrigir eventuais erros de compilação no Delphi 13 real.
- Adicionar notifiers (`IOTAIDENotifier`/`IOTAEditorNotifier`) para reagir
  a eventos da IDE.
- Melhorar o Class Browser para cobrir o projeto inteiro.
- Docking nativo para a janela de resultados do Grep.
