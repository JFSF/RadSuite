unit RadSuite.Tools.InitializationTree;

interface

procedure ShowInitializationTree;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Collections,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

{
  Estima a ordem de inicialização das units do projeto, a partir de uma
  ordenação topológica do grafo de dependências da cláusula uses da
  interface (apenas entre units do próprio projeto). É uma aproximação:
  a ordem real do linker também depende da ordem no .dpr e das cláusulas
  uses da implementation, que aqui não são consideradas.
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

function ExtractInterfaceUses(const SourceText: string): TArray<string>;
var
  RE: TRegEx;
  M: TMatch;
  InterfacePos, SearchEnd: Integer;
  UsesRE: TRegEx;
  UsesMatch: TMatch;
  List: TStringList;
  U: string;
begin
  List := TStringList.Create;
  try
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    RE := TRegEx.Create('\binterface\b', [roIgnoreCase]);
    M := RE.Match(SourceText);
    if M.Success then
    begin
      InterfacePos := M.Index + M.Length;
      RE := TRegEx.Create('\bimplementation\b', [roIgnoreCase]);
      M := RE.Match(SourceText, InterfacePos);
      if M.Success then
        SearchEnd := M.Index
      else
        SearchEnd := Length(SourceText);

      UsesRE := TRegEx.Create('\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
      UsesMatch := UsesRE.Match(SourceText, InterfacePos);
      if UsesMatch.Success and (UsesMatch.Index < SearchEnd) then
        for U in ParseUnitList(UsesMatch.Groups[1].Value) do
          List.Add(U);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function TopoSort(const Deps: TDictionary<string, TArray<string>>; out Unordered: TArray<string>): TArray<string>;
var
  InDegree: TDictionary<string, Integer>;
  Dependents: TObjectDictionary<string, TStringList>;
  Name, Dep, Current: string;
  Queue: TQueue<string>;
  Order: TStringList;
  UnorderedList: TStringList;
begin
  InDegree := TDictionary<string, Integer>.Create;
  Dependents := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  Queue := TQueue<string>.Create;
  Order := TStringList.Create;
  UnorderedList := TStringList.Create;
  try
    for Name in Deps.Keys do
      InDegree.AddOrSetValue(Name, 0);

    for Name in Deps.Keys do
      for Dep in Deps[Name] do
        if InDegree.ContainsKey(Dep) then
        begin
          InDegree[Name] := InDegree[Name] + 1;
          if not Dependents.ContainsKey(Dep) then
            Dependents.Add(Dep, TStringList.Create);
          Dependents[Dep].Add(Name);
        end;

    for Name in InDegree.Keys do
      if InDegree[Name] = 0 then
        Queue.Enqueue(Name);

    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      Order.Add(Current);
      if Dependents.ContainsKey(Current) then
        for Dep in Dependents[Current] do
        begin
          InDegree[Dep] := InDegree[Dep] - 1;
          if InDegree[Dep] = 0 then
            Queue.Enqueue(Dep);
        end;
    end;

    for Name in Deps.Keys do
      if Order.IndexOf(Name) < 0 then
        UnorderedList.Add(Name);

    Result := Order.ToStringArray;
    Unordered := UnorderedList.ToStringArray;
  finally
    InDegree.Free;
    Dependents.Free;
    Queue.Free;
    Order.Free;
    UnorderedList.Free;
  end;
end;

type
  TfrmInitializationTree = class(TForm)
  private
    FListView: TListView;
    FStatusLabel: TLabel;
    FUnitFiles: TDictionary<string, string>;
    procedure Analyze;
    procedure ListDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TfrmInitializationTree.Create(AOwner: TComponent);
var
  Top: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'Show Initialization Tree';
  ClientWidth := 480;
  ClientHeight := 560;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Show Initialization Tree',
    'Ordem aproximada de inicialização (baseada só no uses da interface)');

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.WordWrap := True;
  FStatusLabel.Caption := '';

  FListView := TListView.Create(Self);
  FListView.Parent := Self;
  FListView.Top := Top;
  FListView.Align := alClient;
  FListView.ViewStyle := vsReport;
  FListView.RowSelect := True;
  FListView.GridLines := True;
  FListView.OnDblClick := ListDblClick;
  with FListView.Columns.Add do begin Caption := '#'; Width := 40; end;
  with FListView.Columns.Add do begin Caption := 'Unit'; Width := 380; end;

  FUnitFiles := TDictionary<string, string>.Create;
  Analyze;
end;

destructor TfrmInitializationTree.Destroy;
begin
  FUnitFiles.Free;
  inherited;
end;

procedure TfrmInitializationTree.Analyze;
var
  Project: IOTAProject;
  Files: TArray<string>;
  F, SimpleName: string;
  Deps: TDictionary<string, TArray<string>>;
  Order, Unordered: TArray<string>;
  I: Integer;
  Item: TListItem;
begin
  Project := GetActiveProject;
  if Project = nil then
  begin
    FStatusLabel.Caption := 'Nenhum projeto ativo.';
    Exit;
  end;

  Files := GetProjectSourceFiles(Project);
  Deps := TDictionary<string, TArray<string>>.Create;
  try
    for F in Files do
      if SameText(ExtractFileExt(F), '.pas') then
        FUnitFiles.AddOrSetValue(TPath.GetFileNameWithoutExtension(F), F);

    for SimpleName in FUnitFiles.Keys do
      try
        Deps.Add(SimpleName, ExtractInterfaceUses(GetFileContent(FUnitFiles[SimpleName])));
      except
        Deps.Add(SimpleName, []);
      end;

    Order := TopoSort(Deps, Unordered);

    FListView.Items.BeginUpdate;
    try
      FListView.Items.Clear;
      for I := 0 to High(Order) do
      begin
        Item := FListView.Items.Add;
        Item.Caption := IntToStr(I + 1);
        Item.SubItems.Add(Order[I]);
      end;
      for I := 0 to High(Unordered) do
      begin
        Item := FListView.Items.Add;
        Item.Caption := '?';
        Item.SubItems.Add(Unordered[I] + ' (possível ciclo/indeterminado)');
      end;
    finally
      FListView.Items.EndUpdate;
    end;

    if Length(Unordered) > 0 then
      FStatusLabel.Caption := Format('%d unit(s) ordenada(s), %d não determinada(s).',
        [Length(Order), Length(Unordered)])
    else
      FStatusLabel.Caption := Format('%d unit(s) ordenada(s).', [Length(Order)]);
  finally
    Deps.Free;
  end;
end;

procedure TfrmInitializationTree.ListDblClick(Sender: TObject);
var
  UnitName: string;
begin
  if FListView.Selected = nil then
    Exit;
  UnitName := StringReplace(FListView.Selected.SubItems[0], ' (possível ciclo/indeterminado)', '', []);
  if FUnitFiles.ContainsKey(UnitName) then
    GotoEditorLine(FUnitFiles[UnitName], 1);
end;

procedure ShowInitializationTree;
var
  Form: TfrmInitializationTree;
begin
  Form := TfrmInitializationTree.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
