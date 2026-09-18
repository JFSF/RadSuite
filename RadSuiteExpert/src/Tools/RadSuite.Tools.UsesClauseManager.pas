unit RadSuite.Tools.UsesClauseManager;

interface

procedure ShowUsesClauseManager;

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions, System.StrUtils,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

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

type
  TfrmUsesManager = class(TForm)
  private
    FEditor: IOTASourceEditor;
    FFullText: string;
    FHasInterface, FHasImplementation: Boolean;
    FInterfaceStart, FInterfaceEnd: Integer;
    FImplementationStart, FImplementationEnd: Integer;
    FInterfaceUnits, FImplementationUnits: TStringList;
    FPageControl: TPageControl;
    FInterfaceList, FImplementationList: TListView;
    FStatusLabel: TLabel;
    procedure AnalyzeSource;
    function BuildOutsideText: string;
    procedure PopulateList(AList: TListView; AUnits: TStringList);
    procedure RemoveCheckedClick(Sender: TObject);
    procedure SortClick(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    function CurrentListAndUnits(out AList: TListView; out AUnits: TStringList): Boolean;
    function LocateUses(FromPos: Integer; out CStart, CEnd: Integer; out UnitsText: string): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TfrmUsesManager.Create(AOwner: TComponent);
var
  Top: Integer;
  ButtonPanel: TPanel;
  RemoveButton, SortButton, ApplyButton: TButton;
  InterfaceTab, ImplementationTab: TTabSheet;

  procedure SetupListView(AView: TListView);
  begin
    AView.ViewStyle := vsReport;
    AView.Checkboxes := True;
    AView.RowSelect := True;
    AView.GridLines := True;
    with AView.Columns.Add do begin Caption := 'Unit'; Width := 260; end;
    with AView.Columns.Add do begin Caption := 'Sugestão'; Width := 180; end;
  end;

begin
  inherited CreateNew(AOwner);
  Caption := 'Uses Clause Manager';
  ClientWidth := 560;
  ClientHeight := 520;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  FInterfaceUnits := TStringList.Create;
  FImplementationUnits := TStringList.Create;

  Top := AddRadSuiteHeader(Self, 'Uses Clause Manager',
    'Organiza a cláusula uses da unit ativa no editor');

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  RemoveButton := TButton.Create(Self);
  RemoveButton.Parent := ButtonPanel;
  RemoveButton.Caption := 'Remover marcadas';
  RemoveButton.Left := 12;
  RemoveButton.Top := 8;
  RemoveButton.Width := 140;
  RemoveButton.OnClick := RemoveCheckedClick;

  SortButton := TButton.Create(Self);
  SortButton.Parent := ButtonPanel;
  SortButton.Caption := 'Ordenar A-Z';
  SortButton.Left := 160;
  SortButton.Top := 8;
  SortButton.Width := 110;
  SortButton.OnClick := SortClick;

  ApplyButton := TButton.Create(Self);
  ApplyButton.Parent := ButtonPanel;
  ApplyButton.Caption := 'Aplicar ao editor';
  ApplyButton.Left := 280;
  ApplyButton.Top := 8;
  ApplyButton.Width := 130;
  ApplyButton.OnClick := ApplyClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.Caption := '';

  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := Self;
  FPageControl.Top := Top;
  FPageControl.Align := alClient;

  InterfaceTab := TTabSheet.Create(Self);
  InterfaceTab.PageControl := FPageControl;
  InterfaceTab.Caption := 'Interface';

  ImplementationTab := TTabSheet.Create(Self);
  ImplementationTab.PageControl := FPageControl;
  ImplementationTab.Caption := 'Implementation';

  FInterfaceList := TListView.Create(Self);
  FInterfaceList.Parent := InterfaceTab;
  FInterfaceList.Align := alClient;
  SetupListView(FInterfaceList);

  FImplementationList := TListView.Create(Self);
  FImplementationList.Parent := ImplementationTab;
  FImplementationList.Align := alClient;
  SetupListView(FImplementationList);

  FEditor := GetActiveSourceEditor;
  if FEditor = nil then
  begin
    FStatusLabel.Caption := 'Nenhum editor de código ativo.';
    Exit;
  end;
  FFullText := GetEditorText(FEditor);
  AnalyzeSource;

  if FHasInterface then
    PopulateList(FInterfaceList, FInterfaceUnits)
  else
    InterfaceTab.TabVisible := False;

  if FHasImplementation then
    PopulateList(FImplementationList, FImplementationUnits)
  else
    ImplementationTab.TabVisible := False;

  if not FHasInterface and not FHasImplementation then
    FStatusLabel.Caption := 'Não foi encontrada nenhuma cláusula uses neste ficheiro.';
end;

destructor TfrmUsesManager.Destroy;
begin
  FInterfaceUnits.Free;
  FImplementationUnits.Free;
  inherited;
end;

function TfrmUsesManager.LocateUses(FromPos: Integer; out CStart, CEnd: Integer; out UnitsText: string): Boolean;
var
  UsesRE: TRegEx;
  UsesMatch: TMatch;
begin
  Result := False;
  if FromPos > Length(FFullText) then
    Exit;
  UsesRE := TRegEx.Create('\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
  UsesMatch := UsesRE.Match(FFullText, FromPos);
  if UsesMatch.Success then
  begin
    CStart := UsesMatch.Index;
    CEnd := UsesMatch.Index + UsesMatch.Length - 1;
    UnitsText := UsesMatch.Groups[1].Value;
    Result := True;
  end;
end;

procedure TfrmUsesManager.AnalyzeSource;
var
  RE: TRegEx;
  M: TMatch;
  InterfacePos, ImplementationPos: Integer;
  ClauseStart, ClauseEnd: Integer;
  UnitsText: string;
  U: string;
begin
  FHasInterface := False;
  FHasImplementation := False;
  ImplementationPos := 0;

  RE := TRegEx.Create('\binterface\b', [roIgnoreCase]);
  M := RE.Match(FFullText);
  if M.Success then
  begin
    InterfacePos := M.Index + M.Length;
    RE := TRegEx.Create('\bimplementation\b', [roIgnoreCase]);
    M := RE.Match(FFullText, InterfacePos);
    if M.Success then
      ImplementationPos := M.Index;

    if LocateUses(InterfacePos, ClauseStart, ClauseEnd, UnitsText) and
       ((ImplementationPos = 0) or (ClauseStart < ImplementationPos)) then
    begin
      FHasInterface := True;
      FInterfaceStart := ClauseStart;
      FInterfaceEnd := ClauseEnd;
      for U in ParseUnitList(UnitsText) do
        FInterfaceUnits.Add(U);
    end;

    if ImplementationPos > 0 then
      if LocateUses(ImplementationPos, ClauseStart, ClauseEnd, UnitsText) then
      begin
        FHasImplementation := True;
        FImplementationStart := ClauseStart;
        FImplementationEnd := ClauseEnd;
        for U in ParseUnitList(UnitsText) do
          FImplementationUnits.Add(U);
      end;
  end
  else if LocateUses(1, ClauseStart, ClauseEnd, UnitsText) then
  begin
    // Ficheiro sem interface/implementation (ex.: .dpr/.dpk) - trata como uma única cláusula.
    FHasInterface := True;
    FInterfaceStart := ClauseStart;
    FInterfaceEnd := ClauseEnd;
    for U in ParseUnitList(UnitsText) do
      FInterfaceUnits.Add(U);
  end;
end;

function TfrmUsesManager.BuildOutsideText: string;
begin
  Result := FFullText;
  if FHasImplementation then
    Delete(Result, FImplementationStart, FImplementationEnd - FImplementationStart + 1);
  if FHasInterface then
    Delete(Result, FInterfaceStart, FInterfaceEnd - FInterfaceStart + 1);
end;

procedure TfrmUsesManager.PopulateList(AList: TListView; AUnits: TStringList);
var
  OutsideText: string;
  I: Integer;
  Item: TListItem;
  UsedElsewhere: Boolean;
begin
  OutsideText := BuildOutsideText;
  AList.Items.BeginUpdate;
  try
    AList.Items.Clear;
    for I := 0 to AUnits.Count - 1 do
    begin
      Item := AList.Items.Add;
      Item.Caption := AUnits[I];
      Item.Checked := False;
      try
        UsedElsewhere := TRegEx.IsMatch(OutsideText, '\b' + TRegEx.Escape(AUnits[I]) + '\b', [roIgnoreCase]);
      except
        UsedElsewhere := True;
      end;
      if UsedElsewhere then
        Item.SubItems.Add('')
      else
        Item.SubItems.Add('possivelmente não usada');
    end;
  finally
    AList.Items.EndUpdate;
  end;
end;

function TfrmUsesManager.CurrentListAndUnits(out AList: TListView; out AUnits: TStringList): Boolean;
begin
  Result := True;
  if FPageControl.ActivePage.Caption = 'Interface' then
  begin
    AList := FInterfaceList;
    AUnits := FInterfaceUnits;
  end
  else if FPageControl.ActivePage.Caption = 'Implementation' then
  begin
    AList := FImplementationList;
    AUnits := FImplementationUnits;
  end
  else
    Result := False;
end;

procedure TfrmUsesManager.RemoveCheckedClick(Sender: TObject);
var
  AList: TListView;
  AUnits: TStringList;
  I: Integer;
  Removed: Integer;
begin
  if not CurrentListAndUnits(AList, AUnits) then
    Exit;
  Removed := 0;
  for I := AList.Items.Count - 1 downto 0 do
    if AList.Items[I].Checked then
    begin
      AUnits.Delete(I);
      Inc(Removed);
    end;
  PopulateList(AList, AUnits);
  FStatusLabel.Caption := Format('%d unit(s) removida(s) da lista (ainda não aplicado ao editor).', [Removed]);
end;

procedure TfrmUsesManager.SortClick(Sender: TObject);
var
  AList: TListView;
  AUnits: TStringList;
begin
  if not CurrentListAndUnits(AList, AUnits) then
    Exit;
  AUnits.Sort;
  PopulateList(AList, AUnits);
end;

procedure TfrmUsesManager.ApplyClick(Sender: TObject);
var
  NewText, Replacement: string;
begin
  if FEditor = nil then
    Exit;
  NewText := FFullText;
  if FHasImplementation then
  begin
    Replacement := BuildUsesText(FImplementationUnits.ToStringArray);
    NewText := Copy(NewText, 1, FImplementationStart - 1) + Replacement +
      Copy(NewText, FImplementationEnd + 1, MaxInt);
  end;
  if FHasInterface then
  begin
    Replacement := BuildUsesText(FInterfaceUnits.ToStringArray);
    NewText := Copy(NewText, 1, FInterfaceStart - 1) + Replacement +
      Copy(NewText, FInterfaceEnd + 1, MaxInt);
  end;
  SetEditorText(FEditor, NewText);
  FStatusLabel.Caption := 'Alterações aplicadas ao editor.';
end;

procedure ShowUsesClauseManager;
var
  Form: TfrmUsesManager;
begin
  Form := TfrmUsesManager.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
