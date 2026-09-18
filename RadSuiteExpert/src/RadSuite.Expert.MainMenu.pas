unit RadSuite.Expert.MainMenu;

interface

uses
  System.Classes, Vcl.Menus;

type
  TRadSuiteMenuController = class
  private
    FRootMenuItem: TMenuItem;
    function AddItem(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
    procedure DoAsciiChart(Sender: TObject);
    procedure DoPEInformation(Sender: TObject);
    procedure DoCleanDirectories(Sender: TObject);
    procedure DoCodeLibrarian(Sender: TObject);
    procedure DoUsesClauseManager(Sender: TObject);
    procedure DoClassBrowser(Sender: TObject);
    procedure DoUnitDependencies(Sender: TObject);
    procedure DoGrepSearch(Sender: TObject);
    procedure DoAIAssistant(Sender: TObject);
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
  RadSuite.Tools.ClassBrowser,
  RadSuite.Tools.UnitDependencies,
  RadSuite.Tools.GrepSearch,
  RadSuite.Tools.AIAssistant;

function TRadSuiteMenuController.AddItem(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(nil);
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
  FRootMenuItem.Add(Result);
end;

constructor TRadSuiteMenuController.Create;
var
  Services: INTAServices;
begin
  inherited Create;
  if not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;

  FRootMenuItem := TMenuItem.Create(nil);
  FRootMenuItem.Name := 'RadSuiteMainMenuItem';
  FRootMenuItem.Caption := '&RadSuite';
  Services.MainMenu.Items.Add(FRootMenuItem);

  AddItem('&Grep Search && Replace...', DoGrepSearch);
  AddItem('&Uses Clause Manager...', DoUsesClauseManager);
  AddItem('&Class Browser...', DoClassBrowser);
  AddItem('&Unit Dependencies...', DoUnitDependencies);
  FRootMenuItem.Add(NewLine);
  AddItem('&Code Librarian...', DoCodeLibrarian);
  AddItem('&AI Assistant...', DoAIAssistant);
  FRootMenuItem.Add(NewLine);
  AddItem('&PE Information...', DoPEInformation);
  AddItem('&ASCII Chart...', DoAsciiChart);
  AddItem('C&lean Directories...', DoCleanDirectories);
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

procedure TRadSuiteMenuController.DoClassBrowser(Sender: TObject);
begin
  ShowClassBrowser;
end;

procedure TRadSuiteMenuController.DoUnitDependencies(Sender: TObject);
begin
  ShowUnitDependencies;
end;

procedure TRadSuiteMenuController.DoGrepSearch(Sender: TObject);
begin
  ShowGrepSearch;
end;

procedure TRadSuiteMenuController.DoAIAssistant(Sender: TObject);
begin
  ShowAIAssistant;
end;

end.
