# RadSuite Expert

Scaffold de um Expert/Wizard para a IDE do Delphi 13, baseado na Open Tools
API (`ToolsAPI`). Serve de ponto de partida para expandir com funcionalidade
real (geração de código, integração com ferramentas externas, etc.).

## Estrutura

```
RadSuiteExpert/
├── RadSuiteExpertD13.dpk      Projeto de package (design-time only)
├── RadSuiteExpertD13.dproj    Ficheiro de projeto (MSBuild)
└── src/
    ├── RadSuite.Expert.Wizard.pas     TRadSuiteWizard (IOTAWizard, IOTAMenuWizard)
    ├── RadSuite.Expert.AboutBox.pas   Registo/remoção da entrada na About Box
    └── RadSuite.Expert.Register.pas   initialization/finalization do package
```

O package está marcado como `{$DESIGNONLY}` — só é carregado pela IDE, nunca
é distribuído com as aplicações compiladas.

## O que faz, atualmente

- Regista-se na IDE via `RegisterPackageWizard`.
- Adiciona uma entrada de menu ("RadSuite Expert...") que mostra uma
  mensagem de exemplo ao ser clicada (`TRadSuiteWizard.Execute`).
- Adiciona uma entrada na About Box do Delphi.

A partir daqui, a lógica real do expert entra em `TRadSuiteWizard.Execute`
(ou em notifiers/serviços adicionais da `ToolsAPI`, conforme o que o plugin
precisar de fazer — ex.: `IOTAIDENotifier`, `IOTAEditorNotifier`,
`IOTAProjectNotifier`, geração de código no editor, etc.).

## Compilar e instalar

> Estes passos assumem o Delphi 13 instalado no Windows. Este scaffold foi
> criado sem acesso a uma instalação do Delphi, portanto o `.dproj` pode
> precisar de um pequeno ajuste automático da IDE (versão do projeto) ao
> abrir pela primeira vez — isso é normal e não afeta o `.dpk`/`.pas`.

1. Abra `RadSuiteExpertD13.dproj` no Delphi 13.
2. Se a IDE pedir para atualizar a versão do projeto, aceite.
3. Compile o package (`Project > Build`).
4. Instale-o: `Component > Install Packages... > Add`, e selecione o
   `.bpl` gerado (normalmente em `Win32\Debug\RadSuiteExpertD13.bpl` ou
   `Win64\Debug\...`).
5. Reinicie a IDE. Deverá aparecer:
   - Uma entrada "RadSuite Expert" na About Box (`Help > About`).
   - Uma entrada de menu "RadSuite Expert..." (por omissão, sob o menu
     `Help`, dependendo da versão da IDE).

## Próximos passos possíveis

- Substituir o `ShowMessage` de exemplo pela lógica real do plugin.
- Adicionar um `IOTAIDENotifier`/`IOTAEditorNotifier` para reagir a eventos
  da IDE (abrir ficheiro, compilar, etc.).
- Gerar código no editor ativo via `IOTAEditorServices` /
  `IOTASourceEditor`.
- Adicionar testes/validação com uma segunda instância da IDE (Delphi
  suporta depurar experts anexando o processo `bds.exe` a uma segunda
  instância da própria IDE).
