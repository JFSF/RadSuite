unit RadSuite.Tools.UsesCleaner;

interface

procedure ShowUsesCleaner;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.StrUtils, System.Generics.Collections,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

{
  Versão "todo o projeto" do Uses Clause Manager: aplica a mesma heurística
  textual (nome da unit não aparece fora das cláusulas uses) a todas as
  units do projeto ativo, lidas do disco (ou do editor, se abertas), e
  permite aplicar a remoção nas marcadas.
}

function ParseUnitList(const AText: string): TArray<string>;
var
  Parts: TArray<string>;
  S, Cleaned: string;
  List: TStringList;
  P: Integer;
begin
  List := TStringList.Create;
  try
    Parts := AText.Split([',']);
    for S in Parts do
    begin
      Cleaned := TRegEx.Replace(S, '//.*$', '', [roMultiLine]);
      Cleaned := TRegEx.Replace(Cleaned, '\{.*?\}', '', [roSingleLine]);
      Cleaned := Trim(Cleaned);
      P := Pos(' in ', LowerCase(Cleaned));
      if P > 0 then
        Cleaned := Trim(Copy(Cleaned, 1, P - 1));
      if Cleaned <> '' then
        List.Add(Cleaned);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function BuildUsesText(const Units: TArray<string>): string;
var
  Joined, Line: string;
  I: Integer;
begin
  if Length(Units) = 0 then
    Exit('');
  Joined := string.Join(', ', Units);
  if Length('uses ' + Joined + ';') <= 100 then
    Exit('uses ' + Joined + ';');
  Result := 'uses' + sLineBreak;
  for I := 0 to High(Units) do
  begin
    Line := '  ' + Units[I];
    if I < High(Units) then
      Line := Line + ','
    else
      Line := Line + ';';
    Result := Result + Line + sLineBreak;
  end;
  Result := Result.TrimRight([#13, #10]);
end;

function LocateUses(const FullText: string; FromPos: Integer; out CStart, CEnd: Integer; out UnitsText: string): Boolean;
var
  UsesRE: TRegEx;
  UsesMatch: TMatch;
begin
  Result := False;
  if FromPos > Length(FullText) then
    Exit;
  UsesRE := TRegEx.Create('\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
  UsesMatch := UsesRE.Match(FullText, FromPos);
  if UsesMatch.Success then
  begin
    CStart := UsesMatch.Index;
    CEnd := UsesMatch.Index + UsesMatch.Length - 1;
    UnitsText := UsesMatch.Groups[1].Value;
    Result := True;
  end;
end;

type
  TFileUsesInfo = class
    FileName: string;
    HasInterface, HasImplementation: Boolean;
    IStart, IEnd, PStart, PEnd: Integer;
    InterfaceUnits, ImplementationUnits, Suggestions: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TFileUsesInfo.Create;
begin
  inherited Create;
  InterfaceUnits := TStringList.Create;
  ImplementationUnits := TStringList.Create;
  Suggestions := TStringList.Create;
end;

destructor TFileUsesInfo.Destroy;
begin
  InterfaceUnits.Free;
  ImplementationUnits.Free;
  Suggestions.Free;
  inherited;
end;

procedure AnalyzeFile(const FullText: string; Info: TFileUsesInfo);
var
  RE: TRegEx;
  M: TMatch;
  InterfacePos, ImplementationPos: Integer;
  ClauseStart, ClauseEnd: Integer;
  UnitsText: string;
  U: string;
begin
  Info.HasInterface := False;
  Info.HasImplementation := False;
  ImplementationPos := 0;

  RE := TRegEx.Create('\binterface\b', [roIgnoreCase]);
  M := RE.Match(FullText);
  if not M.Success then
    Exit;
  InterfacePos := M.Index + M.Length;
  RE := TRegEx.Create('\bimplementation\b', [roIgnoreCase]);
  M := RE.Match(FullText, InterfacePos);
  if M.Success then
    ImplementationPos := M.Index;

  if LocateUses(FullText, InterfacePos, ClauseStart, ClauseEnd, UnitsText) and
     ((ImplementationPos = 0) or (ClauseStart < ImplementationPos)) then
  begin
    Info.HasInterface := True;
    Info.IStart := ClauseStart;
    Info.IEnd := ClauseEnd;
    for U in ParseUnitList(UnitsText) do
      Info.InterfaceUnits.Add(U);
  end;

  if ImplementationPos > 0 then
    if LocateUses(FullText, ImplementationPos, ClauseStart, ClauseEnd, UnitsText) then
    begin
      Info.HasImplementation := True;
      Info.PStart := ClauseStart;
      Info.PEnd := ClauseEnd;
      for U in ParseUnitList(UnitsText) do
        Info.ImplementationUnits.Add(U);
    end;
end;

function BuildOutsideText(const FullText: string; Info: TFileUsesInfo): string;
begin
  Result := FullText;
  if Info.HasImplementation then
    Delete(Result, Info.PStart, Info.PEnd - Info.PStart + 1);
  if Info.HasInterface then
    Delete(Result, Info.IStart, Info.IEnd - Info.IStart + 1);
end;

procedure ComputeSuggestions(const FullText: string; Info: TFileUsesInfo);
var
  Outside, U: string;
begin
  Outside := BuildOutsideText(FullText, Info);
  Info.Suggestions.Clear;
  for U in Info.InterfaceUnits do
    if not TRegEx.IsMatch(Outside, '\b' + TRegEx.Escape(U) + '\b', [roIgnoreCase]) then
      Info.Suggestions.Add('I: ' + U);
  for U in Info.ImplementationUnits do
    if not TRegEx.IsMatch(Outside, '\b' + TRegEx.Escape(U) + '\b', [roIgnoreCase]) then
      Info.Suggestions.Add('P: ' + U);
end;

type
  TfrmUsesCleaner = class(TForm)
  private
    FInfos: TObjectList<TFileUsesInfo>;
    FListView: TListView;
    FStatusLabel: TLabel;
    procedure Scan;
    procedure ApplyClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TfrmUsesCleaner.Create(AOwner: TComponent);
var
  Top: Integer;
  ButtonPanel: TPanel;
  ApplyButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Uses Cleaner';
  ClientWidth := 640;
  ClientHeight := 540;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Uses Cleaner',
    'Sugestões de units possivelmente não usadas, em todas as units do projeto');

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  ApplyButton := TButton.Create(Self);
  ApplyButton.Parent := ButtonPanel;
  ApplyButton.Left := 12;
  ApplyButton.Top := 8;
  ApplyButton.Width := 180;
  ApplyButton.Caption := 'Aplicar remoção nas marcadas';
  ApplyButton.OnClick := ApplyClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.Caption := '';

  FListView := TListView.Create(Self);
  FListView.Parent := Self;
  FListView.Top := Top;
  FListView.Align := alClient;
  FListView.ViewStyle := vsReport;
  FListView.Checkboxes := True;
  FListView.RowSelect := True;
  FListView.GridLines := True;
  FListView.OnDblClick := ListDblClick;
  with FListView.Columns.Add do begin Caption := 'Unit'; Width := 180; end;
  with FListView.Columns.Add do begin Caption := 'Sugestões'; Width := 400; end;

  FInfos := TObjectList<TFileUsesInfo>.Create(True);
  Scan;
end;

destructor TfrmUsesCleaner.Destroy;
begin
  FInfos.Free;
  inherited;
end;

procedure TfrmUsesCleaner.Scan;
var
  Project: IOTAProject;
  F: string;
  Info: TFileUsesInfo;
  FullText: string;
  Item: TListItem;
begin
  Project := GetActiveProject;
  if Project = nil then
  begin
    FStatusLabel.Caption := 'Nenhum projeto ativo.';
    Exit;
  end;
  FInfos.Clear;
  FListView.Items.Clear;
  for F in GetProjectSourceFiles(Project) do
  begin
    if not SameText(ExtractFileExt(F), '.pas') then
      Continue;
    try
      FullText := GetFileContent(F);
    except
      Continue;
    end;
    Info := TFileUsesInfo.Create;
    Info.FileName := F;
    AnalyzeFile(FullText, Info);
    ComputeSuggestions(FullText, Info);
    FInfos.Add(Info);
    if Info.Suggestions.Count > 0 then
    begin
      Item := FListView.Items.Add;
      Item.Caption := TPath.GetFileNameWithoutExtension(F);
      Item.SubItems.Add(string.Join(', ', Info.Suggestions.ToStringArray));
      Item.Checked := False;
      Item.Data := Pointer(Info);
    end;
  end;
  FStatusLabel.Caption := Format('%d unit(s) com sugestões, de %d analisada(s).',
    [FListView.Items.Count, FInfos.Count]);
end;

procedure TfrmUsesCleaner.ApplyClick(Sender: TObject);
var
  I: Integer;
  Info: TFileUsesInfo;
  FullText, NewText, Replacement, Name: string;
  Editor: IOTASourceEditor;
  AffectedFiles, AffectedUnits: Integer;
  Suggestion: string;
begin
  AffectedFiles := 0;
  AffectedUnits := 0;
  for I := 0 to FListView.Items.Count - 1 do
    if FListView.Items[I].Checked then
      Inc(AffectedFiles);

  if AffectedFiles = 0 then
  begin
    MessageDlg('Nenhuma unit marcada.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if MessageDlg(Format('Remover as units sugeridas em %d ficheiro(s)? Esta ação não pode ser desfeita.',
      [AffectedFiles]), mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  AffectedFiles := 0;
  for I := 0 to FListView.Items.Count - 1 do
  begin
    if not FListView.Items[I].Checked then
      Continue;
    Info := TFileUsesInfo(FListView.Items[I].Data);
    try
      FullText := GetFileContent(Info.FileName);
      for Suggestion in Info.Suggestions do
      begin
        Name := Copy(Suggestion, 4, MaxInt);
        if StartsStr('I: ', Suggestion) then
          Info.InterfaceUnits.Delete(Info.InterfaceUnits.IndexOf(Name))
        else
          Info.ImplementationUnits.Delete(Info.ImplementationUnits.IndexOf(Name));
        Inc(AffectedUnits);
      end;

      NewText := FullText;
      if Info.HasImplementation then
      begin
        Replacement := BuildUsesText(Info.ImplementationUnits.ToStringArray);
        NewText := Copy(NewText, 1, Info.PStart - 1) + Replacement + Copy(NewText, Info.PEnd + 1, MaxInt);
      end;
      if Info.HasInterface then
      begin
        Replacement := BuildUsesText(Info.InterfaceUnits.ToStringArray);
        NewText := Copy(NewText, 1, Info.IStart - 1) + Replacement + Copy(NewText, Info.IEnd + 1, MaxInt);
      end;

      Editor := FindOpenSourceEditor(Info.FileName);
      if Editor <> nil then
        SetEditorText(Editor, NewText)
      else
        TFile.WriteAllText(Info.FileName, NewText, TEncoding.UTF8);
      Inc(AffectedFiles);
    except
      on E: Exception do
        MessageDlg(Format('Falha em "%s": %s', [Info.FileName, E.Message]), mtError, [mbOK], 0);
    end;
  end;

  FStatusLabel.Caption := Format('%d unit(s) removida(s) em %d ficheiro(s).', [AffectedUnits, AffectedFiles]);
  Scan;
end;

procedure TfrmUsesCleaner.ListDblClick(Sender: TObject);
var
  Info: TFileUsesInfo;
begin
  if FListView.Selected = nil then
    Exit;
  Info := TFileUsesInfo(FListView.Selected.Data);
  GotoEditorLine(Info.FileName, 1);
end;

procedure ShowUsesCleaner;
var
  Form: TfrmUsesCleaner;
begin
  Form := TfrmUsesCleaner.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
