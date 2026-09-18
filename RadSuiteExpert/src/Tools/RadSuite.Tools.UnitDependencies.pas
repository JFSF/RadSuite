unit RadSuite.Tools.UnitDependencies;

interface

procedure ShowUnitDependencies;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.Generics.Collections,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

{
  Analisa as cláusulas uses (interface + implementation) de todas as units
  do projeto ativo, lidas diretamente do disco, e cruza-as com a lista de
  units do próprio projeto para construir um grafo de dependências simples
  (quem depende de quem). Não resolve caminhos de procura (search path) nem
  units fora do projeto.
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

function ExtractUsedUnits(const SourceText: string): TArray<string>;
var
  RE: TRegEx;
  M: TMatch;
  List: TStringList;
  U: string;
begin
  List := TStringList.Create;
  try
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    RE := TRegEx.Create('\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
    for M in RE.Matches(SourceText) do
      for U in ParseUnitList(M.Groups[1].Value) do
        List.Add(U);
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

type
  TfrmUnitDependencies = class(TForm)
  private
    FTree: TTreeView;
    FStatusLabel: TLabel;
    FUnitFiles: TDictionary<string, string>; // simple unit name -> file path
    procedure Analyze;
    procedure TreeDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TfrmUnitDependencies.Create(AOwner: TComponent);
var
  Top: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'Unit Dependencies';
  ClientWidth := 520;
  ClientHeight := 600;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Unit Dependencies',
    'Dependências entre as units do projeto ativo (apenas units do próprio projeto)');

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.Caption := '';

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Top := Top;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.OnDblClick := TreeDblClick;

  FUnitFiles := TDictionary<string, string>.Create;
  Analyze;
end;

destructor TfrmUnitDependencies.Destroy;
begin
  FUnitFiles.Free;
  inherited;
end;

procedure TfrmUnitDependencies.Analyze;
var
  Project: IOTAProject;
  Files: TArray<string>;
  F, SimpleName, Used: string;
  SourceMap: TDictionary<string, TArray<string>>; // simple name -> used units (raw)
  UsedBy: TDictionary<string, TStringList>;
  UnitNode, DependsNode, UsedByNode, ChildNode: TTreeNode;
  Names: TArray<string>;
  Name: string;
begin
  Project := GetActiveProject;
  if Project = nil then
  begin
    FStatusLabel.Caption := 'Nenhum projeto ativo.';
    Exit;
  end;

  Files := GetProjectSourceFiles(Project);
  SourceMap := TDictionary<string, TArray<string>>.Create;
  UsedBy := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  try
    for F in Files do
    begin
      if not SameText(ExtractFileExt(F), '.pas') then
        Continue;
      SimpleName := TPath.GetFileNameWithoutExtension(F);
      FUnitFiles.AddOrSetValue(SimpleName, F);
    end;

    for SimpleName in FUnitFiles.Keys do
    begin
      try
        SourceMap.Add(SimpleName, ExtractUsedUnits(TFile.ReadAllText(FUnitFiles[SimpleName])));
      except
        SourceMap.Add(SimpleName, []);
      end;
    end;

    for SimpleName in SourceMap.Keys do
      for Used in SourceMap[SimpleName] do
        if FUnitFiles.ContainsKey(Used) then
        begin
          if not UsedBy.ContainsKey(Used) then
            UsedBy.Add(Used, TStringList.Create);
          UsedBy[Used].Add(SimpleName);
        end;

    FTree.Items.BeginUpdate;
    try
      FTree.Items.Clear;
      Names := SourceMap.Keys.ToArray;
      TArray.Sort<string>(Names);
      for Name in Names do
      begin
        UnitNode := FTree.Items.AddObject(nil, Name, nil);

        DependsNode := FTree.Items.AddChild(UnitNode, 'Depende de');
        for Used in SourceMap[Name] do
          if FUnitFiles.ContainsKey(Used) and not SameText(Used, Name) then
          begin
            ChildNode := FTree.Items.AddChildObject(DependsNode, Used, Pointer(1));
          end;

        UsedByNode := FTree.Items.AddChild(UnitNode, 'É usada por');
        if UsedBy.ContainsKey(Name) then
          for Used in UsedBy[Name] do
            ChildNode := FTree.Items.AddChildObject(UsedByNode, Used, Pointer(1));
      end;
    finally
      FTree.Items.EndUpdate;
    end;

    FStatusLabel.Caption := Format('%d unit(s) analisada(s).', [FUnitFiles.Count]);
  finally
    SourceMap.Free;
    UsedBy.Free;
  end;
end;

procedure TfrmUnitDependencies.TreeDblClick(Sender: TObject);
var
  UnitName: string;
begin
  if (FTree.Selected = nil) or (FTree.Selected.Data = nil) then
    Exit;
  UnitName := FTree.Selected.Text;
  if FUnitFiles.ContainsKey(UnitName) then
    GotoEditorLine(FUnitFiles[UnitName], 1);
end;

procedure ShowUnitDependencies;
var
  Form: TfrmUnitDependencies;
begin
  Form := TfrmUnitDependencies.Create(nil);
  Form.Show;
end;

end.
