# RadSuite Expert

Toolkit de produtividade para a IDE do Delphi 13, baseado na Open Tools API
(`ToolsAPI`). Inspirado no [GExperts](https://www.gexperts.org/), no
[CnWizards](https://github.com/cnpack/cnwizards) e no MMX Code Explorer,
reúne um conjunto de ferramentas num único menu **RadSuite** da IDE.

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
        ├── RadSuite.Tools.UsesCleaner.pas
        ├── RadSuite.Tools.ClassBrowser.pas
        ├── RadSuite.Tools.UnitDependencies.pas
        ├── RadSuite.Tools.InitializationTree.pas
        ├── RadSuite.Tools.CodeMap.pas
        ├── RadSuite.Tools.CodeLibrarian.pas
        ├── RadSuite.Tools.AddMember.pas
        ├── RadSuite.Tools.AIAssistant.pas
        ├── RadSuite.Tools.SourceTemplates.pas
        ├── RadSuite.Tools.TextTools.pas
        ├── RadSuite.Tools.ProjectOptionSets.pas
        ├── RadSuite.Tools.ProjectBackup.pas
        ├── RadSuite.Tools.ProjectDirBuilder.pas
        ├── RadSuite.Tools.ListUnits.pas
        ├── RadSuite.Tools.PEInformation.pas
        ├── RadSuite.Tools.AsciiChart.pas
        └── RadSuite.Tools.CleanDirectories.pas
```

O package está marcado como `{$DESIGNONLY}` — só é carregado pela IDE, nunca
é distribuído com as aplicações compiladas. Todas as janelas são construídas
inteiramente por código (sem `.dfm`), para evitar problemas de recursos
binários entre versões do Delphi.

## Ferramentas incluídas

Acessíveis a partir do menu **RadSuite** da IDE (algumas dentro dos
submenus **Source Templates** e **Text Tools**):

| Ferramenta | O que faz |
|---|---|
| **Grep Search & Replace** | Procura (texto ou regex) em ficheiros abertos, no projeto ativo ou numa pasta; janela não-modal com resultados navegáveis (duplo-clique salta para a ocorrência); substituição em lote nos ficheiros marcados, com confirmação. |
| **Uses Clause Manager** | Lista as units das cláusulas `uses` (interface/implementation) da unit ativa; sinaliza como sugestão as que não aparecem em mais nenhum sítio do ficheiro (heurística textual); permite remover/ordenar e aplicar ao editor. |
| **Uses Cleaner (projeto)** | Versão em lote do Uses Clause Manager: aplica a mesma heurística a todas as units do projeto, lista sugestões por unit e aplica a remoção nas marcadas. |
| **Class Browser** | Árvore de classes → métodos/propriedades/campos da unit ativa, detetados por expressões regulares; duplo-clique navega até à declaração. Menu de contexto "Adicionar Membro..." abre o Add Member. |
| **Unit Dependencies** | Lê as cláusulas `uses` de todas as units do projeto ativo e mostra, por unit, de que outras units do projeto depende e por quais é usada. |
| **Show Initialization Tree** | Estima a ordem de inicialização das units do projeto por ordenação topológica do grafo de `uses` da interface; assinala ciclos/indeterminações. |
| **Code Map & Checklist** | Gera uma página HTML offline (árvore de units do projeto, métodos por unit, checklist com progresso/estrela/notas/Compila/Sonar, exportação JSON/Markdown/CSV) e mantém-na atualizada por vigilância periódica enquanto a janela estiver aberta — ver secção própria abaixo. |
| **List Units** | Lista filtrável (à medida que escreve) das units do projeto, com navegação por Enter/duplo-clique. |
| **Code Librarian** | Gestor de snippets de código por categorias, guardados em `%APPDATA%\RadSuite\CodeLibrary.txt`; insere o snippet selecionado no editor ativo. |
| **Add Member** | Diálogo unificado que gera esqueletos Pascal (campo, método, propriedade, procedure/function avulsa, class, interface, record, variável local) e insere-os no cursor. |
| **AI Assistant** | Painel de prompt com resposta da API Claude (Anthropic); pode incluir o código selecionado como contexto; insere ou substitui a seleção no editor com a resposta. Requer API key própria (ver secção abaixo). |
| **Source Templates → Pascal Unit Header** | Insere um bloco de cabeçalho no topo do ficheiro (nome da unit detetado automaticamente). |
| **Source Templates → Pascal Procedure Header** | Insere um bloco de cabeçalho de documentação acima do cursor (tenta detetar o nome do procedimento seguinte). |
| **Text Tools → Align Code** | Alinha o primeiro `:=` ou `:` de cada linha selecionada na mesma coluna. |
| **Text Tools → Untabify / Tabify** | Converte tabs em espaços e vice-versa na seleção. |
| **Text Tools → Convert Code To String** | Converte as linhas selecionadas numa literal Pascal (`'linha' + sLineBreak + ...`), com aspas escapadas. |
| **Text Tools → Sort text** | Ordena alfabeticamente as linhas selecionadas. |
| **Text Tools → Format Uses Clause / Alternate** | Reformata (sem alterar a lista de units) a cláusula `uses` mais próxima do cursor: uma unit por linha, ou tudo numa linha (Alternate). |
| **Project Option Sets** | Guarda/aplica conjuntos nomeados de opções de compilação (Output dir, Unit output dir, Conditional defines, Debug info, Optimization) via `IOTAProjectOptionsConfigurations`. |
| **Project Backup** | Cria um `.zip` do código-fonte do projeto ativo (`System.Zip`), por omissão numa pasta irmã `Backups` fora da pasta do projeto. |
| **Project Dir Builder** | Cria a estrutura de pastas indicada numa lista editável (um caminho relativo por linha), a partir da pasta base escolhida. |
| **PE Information** | Inspetor de ficheiros PE (EXE/DLL/BPL): DOS/NT headers, secções, imports e exports, lidos diretamente do binário (32 e 64-bit). |
| **ASCII Chart** | Tabela de caracteres ASCII 0-255 (decimal/hex/carácter), com cópia para a clipboard. |
| **Clean Directories** | Varre a pasta do projeto (ou outra à escolha) por ficheiros temporários/intermédios do Delphi (`.dcu`, `.~*`, `.local`, `__history`, etc.) e permite apagar os selecionados, com confirmação. |

### Code Map & Checklist — detalhe

Funde, em Delphi, a lógica de dois scripts PowerShell equivalentes (um gerador
de mapa de código, outro de checklist), e acrescenta vigilância automática:

- As units mostradas são as **registadas no projeto ativo do Delphi**
  (via `IOTAProject`/`GetModule`), não uma varredura de pastas — por isso
  não há lista de pastas a ignorar como nos scripts originais.
- Os métodos de cada unit são extraídos com a mesma heurística textual
  (regex) usada no resto do RadSuite, não um parser Delphi completo.
- **Vigilância (polling)**: ao clicar "Iniciar vigilância", um `TTimer`
  volta a ler a lista de units do projeto a cada N segundos (configurável);
  se mudou (unit nova, apagada ou renomeada), a página é regenerada
  automaticamente no disco, sem precisar de clicar "Atualizar".
- A página HTML tem um botão de "auto-atualizar" (ícone ↻ no cabeçalho,
  estado guardado no navegador) que, quando ligado, recarrega a própria
  página a cada poucos segundos — útil para ver as units novas aparecerem
  em tempo real sem premir F5.
- Uma "cache" local (`%APPDATA%\RadSuite\CodeMap_<slug>.cache.txt`) guarda
  a lista de units da última geração, para assinalar com um selo **NOVO**
  as units criadas desde então.
- O progresso (concluído/estrela/notas/Compila/Sonar, por ficheiro e por
  método) fica guardado no `localStorage` do navegador — regenerar a
  página não apaga o progresso já registado.
- Botões "Fechar como finalizado" / "Reabrir projeto" adicionam ou removem
  o selo "PROJETO FINALIZADO" no topo da página.

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
   - Um menu **RadSuite** na barra de menus principal, com todas as
     ferramentas (algumas dentro de **Source Templates** e **Text Tools**).

## Limitações conhecidas (âmbito v1)

- **Uses Clause Manager / Uses Cleaner**: a deteção de units "possivelmente
  não usadas" é uma heurística textual (procura o nome no resto do
  ficheiro), pode ter falsos positivos/negativos — a remoção é sempre
  confirmada antes de aplicar.
- **Class Browser**: analisa apenas a unit ativa no editor, via regex —
  não resolve tipos aninhados, genéricos complexos ou heranças fora da unit.
- **Unit Dependencies / Show Initialization Tree**: só consideram as units
  do próprio projeto (lidas do disco), não resolvem o search path completo
  nem units externas. A ordem de inicialização é uma aproximação baseada só
  no `uses` da interface — a ordem real também depende do `.dpr` e das
  cláusulas `uses` da implementation.
- **Add Member / Source Templates**: geram esqueletos de código e inserem-
  nos na posição do cursor — não localizam automaticamente a secção
  correta da classe (private/public/etc.) nem separam declaração de
  implementação. Não são um "modelo de código ao vivo".
- **Project Option Sets**: cobre apenas um subconjunto curado de opções
  (Output dir, Unit output dir, Conditional defines, Debug info,
  Optimization), não a totalidade das opções do projeto.
- **Grep Search & Replace**: janela não-modal simples, sem docking nativo
  na IDE.
- **Code Map & Checklist**: a vigilância é por *polling* (intervalo
  configurável), não por notificação instantânea da IDE — uma unit nova
  só é detetada no próximo ciclo. O auto-reload da própria página HTML
  também é por intervalo fixo (8s), não instantâneo.
- Nenhum destes ficheiros foi compilado/testado num Delphi real — ver nota
  acima.

## Próximos passos possíveis

- Testar e corrigir eventuais erros de compilação no Delphi 13 real.
- Adicionar notifiers (`IOTAIDENotifier`/`IOTAEditorNotifier`) para reagir
  a eventos da IDE.
- Melhorar o Class Browser para cobrir o projeto inteiro.
- Docking nativo para a janela de resultados do Grep.
- Add Member: localizar automaticamente a secção da classe em vez de
  inserir sempre no cursor.
