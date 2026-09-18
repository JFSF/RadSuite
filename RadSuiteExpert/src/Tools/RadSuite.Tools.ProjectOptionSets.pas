unit RadSuite.Tools.ProjectOptionSets;

interface

procedure ShowProjectOptionSets;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

{
  Guarda/aplica um subconjunto curado de opções de compilação (as mesmas
  propriedades usadas nos ficheiros .dproj: DCC_ExeOutput, DCC_DcuOutput,
  DCC_Define, DCC_DebugInformation, DCC_Optimize) via
  IOTAProjectOptionsConfigurations / IOTABuildConfiguration. Não tenta
  replicar a totalidade das opções do projeto.
}

const
  OptionKeys: array[0..4] of string = (
    'DCC_ExeOutput', 'DCC_DcuOutput', 'DCC_Define', 'DCC_DebugInformation', 'DCC_Optimize');
  OptionLabels: array[0..4] of string = (
    'Output dir (DCC_ExeOutput)', 'Unit output dir (DCC_DcuOutput)',
    'Conditional defines (DCC_Define)', 'Debug information (DCC_DebugInformation)',
    'Optimization (DCC_Optimize)');

function GetSetsFilePath: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'RadSuite'), 'OptionSets.ini');
end;

function GetActiveBuildConfig(const Project: IOTAProject): IOTABuildConfiguration;
var
  Configs: IOTAProjectOptionsConfigurations;
begin
  Result := nil;
  if (Project = nil) or (Project.ProjectOptions = nil) then
    Exit;
  if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    Result := Configs.ActiveConfiguration;
end;

type
  TfrmProjectOptionSets = class(TForm)
  private
    FSetsListBox: TListBox;
    FValuesMemo: TMemo;
    FStatusLabel: TLabel;
    procedure RefreshSetsList;
    procedure SetsListClick(Sender: TObject);
    procedure SaveNewClick(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmProjectOptionSets.Create(AOwner: TComponent);
var
  Top: Integer;
  ButtonPanel: TPanel;
  SaveButton, ApplyButton, DeleteButton: TButton;
  Splitter: TSplitter;
begin
  inherited CreateNew(AOwner);
  Caption := 'Project Option Sets';
  ClientWidth := 620;
  ClientHeight := 480;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Project Option Sets',
    'Guarda e aplica conjuntos de opções de compilação ao projeto ativo');

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  SaveButton := TButton.Create(Self);
  SaveButton.Parent := ButtonPanel;
  SaveButton.Left := 12;
  SaveButton.Top := 8;
  SaveButton.Width := 170;
  SaveButton.Caption := 'Guardar estado atual como...';
  SaveButton.OnClick := SaveNewClick;

  ApplyButton := TButton.Create(Self);
  ApplyButton.Parent := ButtonPanel;
  ApplyButton.Left := 190;
  ApplyButton.Top := 8;
  ApplyButton.Width := 130;
  ApplyButton.Caption := 'Aplicar ao projeto';
  ApplyButton.OnClick := ApplyClick;

  DeleteButton := TButton.Create(Self);
  DeleteButton.Parent := ButtonPanel;
  DeleteButton.Left := 328;
  DeleteButton.Top := 8;
  DeleteButton.Width := 90;
  DeleteButton.Caption := 'Apagar';
  DeleteButton.OnClick := DeleteClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.Caption := '';

  FSetsListBox := TListBox.Create(Self);
  FSetsListBox.Parent := Self;
  FSetsListBox.Top := Top;
  FSetsListBox.Left := 0;
  FSetsListBox.Width := 220;
  FSetsListBox.Align := alLeft;
  FSetsListBox.OnClick := SetsListClick;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Left := 220;
  Splitter.Top := Top;
  Splitter.Width := 4;

  FValuesMemo := TMemo.Create(Self);
  FValuesMemo.Parent := Self;
  FValuesMemo.Top := Top;
  FValuesMemo.Align := alClient;
  FValuesMemo.ReadOnly := True;
  FValuesMemo.ScrollBars := ssBoth;
  FValuesMemo.Font.Name := 'Consolas';
  FValuesMemo.Font.Size := 9;

  RefreshSetsList;
end;

procedure TfrmProjectOptionSets.RefreshSetsList;
var
  Ini: TIniFile;
  Sections: TStringList;
begin
  FSetsListBox.Items.Clear;
  if not TFile.Exists(GetSetsFilePath) then
    Exit;
  Ini := TIniFile.Create(GetSetsFilePath);
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    FSetsListBox.Items.Assign(Sections);
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

procedure TfrmProjectOptionSets.SetsListClick(Sender: TObject);
var
  Ini: TIniFile;
  I: Integer;
  SetName: string;
begin
  if FSetsListBox.ItemIndex < 0 then
    Exit;
  SetName := FSetsListBox.Items[FSetsListBox.ItemIndex];
  Ini := TIniFile.Create(GetSetsFilePath);
  try
    FValuesMemo.Lines.Clear;
    for I := 0 to High(OptionKeys) do
      FValuesMemo.Lines.Add(OptionLabels[I] + ' = ' + Ini.ReadString(SetName, OptionKeys[I], '(vazio)'));
  finally
    Ini.Free;
  end;
end;

procedure TfrmProjectOptionSets.SaveNewClick(Sender: TObject);
var
  SetName: string;
  Project: IOTAProject;
  Config: IOTABuildConfiguration;
  Ini: TIniFile;
  I: Integer;
begin
  Project := GetActiveProject;
  if Project = nil then
  begin
    MessageDlg('Nenhum projeto ativo.', mtWarning, [mbOK], 0);
    Exit;
  end;
  Config := GetActiveBuildConfig(Project);
  if Config = nil then
  begin
    MessageDlg('Não foi possível aceder às opções do projeto.', mtError, [mbOK], 0);
    Exit;
  end;
  SetName := '';
  if not InputQuery('Guardar conjunto', 'Nome do conjunto de opções:', SetName) then
    Exit;
  if Trim(SetName) = '' then
    Exit;

  TDirectory.CreateDirectory(ExtractFilePath(GetSetsFilePath));
  Ini := TIniFile.Create(GetSetsFilePath);
  try
    for I := 0 to High(OptionKeys) do
      try
        Ini.WriteString(SetName, OptionKeys[I], Config.Value[OptionKeys[I]]);
      except
        Ini.WriteString(SetName, OptionKeys[I], '');
      end;
  finally
    Ini.Free;
  end;
  RefreshSetsList;
  FStatusLabel.Caption := Format('Conjunto "%s" guardado.', [SetName]);
end;

procedure TfrmProjectOptionSets.ApplyClick(Sender: TObject);
var
  Project: IOTAProject;
  Config: IOTABuildConfiguration;
  Ini: TIniFile;
  SetName: string;
  I: Integer;
begin
  if FSetsListBox.ItemIndex < 0 then
  begin
    MessageDlg('Selecione um conjunto.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Project := GetActiveProject;
  if Project = nil then
  begin
    MessageDlg('Nenhum projeto ativo.', mtWarning, [mbOK], 0);
    Exit;
  end;
  Config := GetActiveBuildConfig(Project);
  if Config = nil then
  begin
    MessageDlg('Não foi possível aceder às opções do projeto.', mtError, [mbOK], 0);
    Exit;
  end;
  SetName := FSetsListBox.Items[FSetsListBox.ItemIndex];
  if MessageDlg(Format('Aplicar o conjunto "%s" à configuração ativa do projeto "%s"?',
      [SetName, ExtractFileName(Project.FileName)]), mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Ini := TIniFile.Create(GetSetsFilePath);
  try
    for I := 0 to High(OptionKeys) do
      try
        Config.Value[OptionKeys[I]] := Ini.ReadString(SetName, OptionKeys[I], '');
      except
        // ignora chave que a IDE não aceite nesta versão/plataforma
      end;
  finally
    Ini.Free;
  end;
  FStatusLabel.Caption := 'Conjunto aplicado.';
end;

procedure TfrmProjectOptionSets.DeleteClick(Sender: TObject);
var
  Ini: TIniFile;
  SetName: string;
begin
  if FSetsListBox.ItemIndex < 0 then
    Exit;
  SetName := FSetsListBox.Items[FSetsListBox.ItemIndex];
  if MessageDlg(Format('Apagar o conjunto "%s"?', [SetName]), mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  Ini := TIniFile.Create(GetSetsFilePath);
  try
    Ini.EraseSection(SetName);
  finally
    Ini.Free;
  end;
  RefreshSetsList;
  FValuesMemo.Lines.Clear;
end;

procedure ShowProjectOptionSets;
var
  Form: TfrmProjectOptionSets;
begin
  Form := TfrmProjectOptionSets.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
