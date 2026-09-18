unit RadSuite.Expert.MainMenu;

interface

uses
  System.Classes, Vcl.Menus;

type
  TRadSuiteMenuController = class
  private
    FRootMenuItem: TMenuItem;
    function AddItem(AParent: TMenuItem; const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
    function AddSubMenu(AParent: TMenuItem; const ACaption: string): TMenuItem;
    procedure DoAsciiChart(Sender: TObject);
    procedure DoPEInformation(Sender: TObject);
    procedure DoCleanDirectories(Sender: TObject);
    procedure DoCodeLibrarian(Sender: TObject);
    procedure DoUsesClauseManager(Sender: TObject);
    procedure DoUsesCleaner(Sender: TObject);
    procedure DoClassBrowser(Sender: TObject);
    procedure DoUnitDependencies(Sender: TObject);
    procedure DoInitializationTree(Sender: TObject);
    procedure DoGrepSearch(Sender: TObject);
    procedure DoAIAssistant(Sender: TObject);
    procedure DoProjectOptionSets(Sender: TObject);
    procedure DoListUnits(Sender: TObject);
    procedure DoProjectBackup(Sender: TObject);
    procedure DoProjectDirBuilder(Sender: TObject);
    procedure DoAddMember(Sender: TObject);
    procedure DoUnitHeaderTemplate(Sender: TObject);
    procedure DoProcedureHeaderTemplate(Sender: TObject);
    procedure DoAlignCode(Sender: TObject);
    procedure DoUntabify(Sender: TObject);
    procedure DoTabify(Sender: TObject);
    procedure DoConvertCodeToString(Sender: TObject);
    procedure DoSortText(Sender: TObject);
    procedure DoFormatUsesClause(Sender: TObject);
    procedure DoFormatUsesClauseAlternate(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  ToolsAPI,
  RadSuite.Tools.AsciiChart,
  RadSuite.Tools.PEInformation,
  RadSuite.Tools.CleanDirectories,
  RadSuite.Tools.CodeLibrarian,
  RadSuite.Tools.UsesClauseManager,
  RadSuite.Tools.UsesCleaner,
  RadSuite.Tools.ClassBrowser,
  RadSuite.Tools.UnitDependencies,
  RadSuite.Tools.InitializationTree,
  RadSuite.Tools.GrepSearch,
  RadSuite.Tools.AIAssistant,
  RadSuite.Tools.ProjectOptionSets,
  RadSuite.Tools.ListUnits,
  RadSuite.Tools.ProjectBackup,
  RadSuite.Tools.ProjectDirBuilder,
  RadSuite.Tools.AddMember,
  RadSuite.Tools.SourceTemplates,
  RadSuite.Tools.TextTools;

function TRadSuiteMenuController.AddItem(AParent: TMenuItem; const ACaption: string;
  AHandler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(nil);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  AParent.Add(Result);
end;

function TRadSuiteMenuController.AddSubMenu(AParent: TMenuItem; const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(nil);
  Result.Caption := ACaption;
  AParent.Add(Result);
end;

constructor TRadSuiteMenuController.Create;
var
  Services: INTAServices;
  SourceTemplatesMenu, TextToolsMenu: TMenuItem;
begin
  inherited Create;
  if not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;

  FRootMenuItem := TMenuItem.Create(nil);
  FRootMenuItem.Name := 'RadSuiteMainMenuItem';
  FRootMenuItem.Caption := '&RadSuite';
  Services.MainMenu.Items.Add(FRootMenuItem);

  AddItem(FRootMenuItem, '&Grep Search && Replace...', DoGrepSearch);
  AddItem(FRootMenuItem, '&Uses Clause Manager...', DoUsesClauseManager);
  AddItem(FRootMenuItem, 'Uses &Cleaner (projeto)...', DoUsesCleaner);
  AddItem(FRootMenuItem, '&Class Browser...', DoClassBrowser);
  AddItem(FRootMenuItem, '&Unit Dependencies...', DoUnitDependencies);
  AddItem(FRootMenuItem, 'Show &Initialization Tree...', DoInitializationTree);
  FRootMenuItem.Add(NewLine);
  AddItem(FRootMenuItem, '&List Units...', DoListUnits);
  AddItem(FRootMenuItem, '&Code Librarian...', DoCodeLibrarian);
  AddItem(FRootMenuItem, 'Add &Member...', DoAddMember);
  AddItem(FRootMenuItem, '&AI Assistant...', DoAIAssistant);
  FRootMenuItem.Add(NewLine);

  SourceTemplatesMenu := AddSubMenu(FRootMenuItem, 'Source &Templates');
  AddItem(SourceTemplatesMenu, 'Pascal Unit Header', DoUnitHeaderTemplate);
  AddItem(SourceTemplatesMenu, 'Pascal Procedure Header', DoProcedureHeaderTemplate);

  TextToolsMenu := AddSubMenu(FRootMenuItem, '&Text Tools');
  AddItem(TextToolsMenu, 'Align Code', DoAlignCode);
  AddItem(TextToolsMenu, 'Untabify', DoUntabify);
  AddItem(TextToolsMenu, 'Tabify', DoTabify);
  AddItem(TextToolsMenu, 'Convert Code To String', DoConvertCodeToString);
  AddItem(TextToolsMenu, 'Sort text', DoSortText);
  AddItem(TextToolsMenu, 'Format Uses Clause', DoFormatUsesClause);
  AddItem(TextToolsMenu, 'Format Uses - Alternate', DoFormatUsesClauseAlternate);

  FRootMenuItem.Add(NewLine);
  AddItem(FRootMenuItem, 'Project &Option Sets...', DoProjectOptionSets);
  AddItem(FRootMenuItem, 'Project &Backup...', DoProjectBackup);
  AddItem(FRootMenuItem, 'Project &Dir Builder...', DoProjectDirBuilder);
  AddItem(FRootMenuItem, '&PE Information...', DoPEInformation);
  AddItem(FRootMenuItem, '&ASCII Chart...', DoAsciiChart);
  AddItem(FRootMenuItem, 'C&lean Directories...', DoCleanDirectories);
end;

destructor TRadSuiteMenuController.Destroy;
var
  Services: INTAServices;
begin
  if FRootMenuItem <> nil then
  begin
    if Supports(BorlandIDEServices, INTAServices, Services) then
      Services.MainMenu.Items.Remove(FRootMenuItem);
    FRootMenuItem.Free;
  end;
  inherited;
end;

procedure TRadSuiteMenuController.DoAsciiChart(Sender: TObject);
begin
  ShowAsciiChart;
end;

procedure TRadSuiteMenuController.DoPEInformation(Sender: TObject);
begin
  ShowPEInformation;
end;

procedure TRadSuiteMenuController.DoCleanDirectories(Sender: TObject);
begin
  ShowCleanDirectories;
end;

procedure TRadSuiteMenuController.DoCodeLibrarian(Sender: TObject);
begin
  ShowCodeLibrarian;
end;

procedure TRadSuiteMenuController.DoUsesClauseManager(Sender: TObject);
begin
  ShowUsesClauseManager;
end;

procedure TRadSuiteMenuController.DoUsesCleaner(Sender: TObject);
begin
  ShowUsesCleaner;
end;

procedure TRadSuiteMenuController.DoClassBrowser(Sender: TObject);
begin
  ShowClassBrowser;
end;

procedure TRadSuiteMenuController.DoUnitDependencies(Sender: TObject);
begin
  ShowUnitDependencies;
end;

procedure TRadSuiteMenuController.DoInitializationTree(Sender: TObject);
begin
  ShowInitializationTree;
end;

procedure TRadSuiteMenuController.DoGrepSearch(Sender: TObject);
begin
  ShowGrepSearch;
end;

procedure TRadSuiteMenuController.DoAIAssistant(Sender: TObject);
begin
  ShowAIAssistant;
end;

procedure TRadSuiteMenuController.DoProjectOptionSets(Sender: TObject);
begin
  ShowProjectOptionSets;
end;

procedure TRadSuiteMenuController.DoListUnits(Sender: TObject);
begin
  ShowListUnits;
end;

procedure TRadSuiteMenuController.DoProjectBackup(Sender: TObject);
begin
  ShowProjectBackup;
end;

procedure TRadSuiteMenuController.DoProjectDirBuilder(Sender: TObject);
begin
  ShowProjectDirBuilder;
end;

procedure TRadSuiteMenuController.DoAddMember(Sender: TObject);
begin
  ShowAddMember;
end;

procedure TRadSuiteMenuController.DoUnitHeaderTemplate(Sender: TObject);
begin
  InsertUnitHeaderTemplate;
end;

procedure TRadSuiteMenuController.DoProcedureHeaderTemplate(Sender: TObject);
begin
  InsertProcedureHeaderTemplate;
end;

procedure TRadSuiteMenuController.DoAlignCode(Sender: TObject);
begin
  AlignCode;
end;

procedure TRadSuiteMenuController.DoUntabify(Sender: TObject);
begin
  UntabifySelection;
end;

procedure TRadSuiteMenuController.DoTabify(Sender: TObject);
begin
  TabifySelection;
end;

procedure TRadSuiteMenuController.DoConvertCodeToString(Sender: TObject);
begin
  ConvertCodeToString;
end;

procedure TRadSuiteMenuController.DoSortText(Sender: TObject);
begin
  SortSelectedLines;
end;

procedure TRadSuiteMenuController.DoFormatUsesClause(Sender: TObject);
begin
  FormatUsesClause;
end;

procedure TRadSuiteMenuController.DoFormatUsesClauseAlternate(Sender: TObject);
begin
  FormatUsesClauseAlternate;
end;

end.
