unit RadSuite.Tools.ClassBrowser;

interface

procedure ShowClassBrowser;

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions, System.StrUtils,
  System.Math,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus,
  RadSuite.UI.Theme, RadSuite.IDE.Utils, RadSuite.Tools.AddMember;

{
  Class Browser leve: procura declarações de classes na unit ativa via
  expressões regulares e classifica linhas do corpo da classe como
  métodos/propriedades/campos. Não é uma análise semântica do compilador
  (não resolve heranças de outras units, genéricos complexos ou tipos
  aninhados) - destina-se a navegação rápida dentro da unit aberta.
}

function LineNumberAtPos(const AText: string; APos: Integer): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Min(APos - 1, Length(AText)) do
    if AText[I] = #10 then
      Inc(Result);
end;

function IsSkippableLine(const ALower: string): Boolean;
const
  Keywords: array[0..9] of string = (
    'private', 'public', 'protected', 'published', 'strict private',
    'strict protected', 'end', 'end;', 'type', 'const');
var
  K: string;
begin
  Result := False;
  for K in Keywords do
    if ALower = K then
      Exit(True);
  if StartsText('//', ALower) or StartsText('{', ALower) or StartsText('[', ALower) then
    Exit(True);
end;

function ClassifyMember(const ATrimmedLine: string; out AKind, AName: string): Boolean;
var
  M: TMatch;
begin
  Result := False;
  if (ATrimmedLine = '') or IsSkippableLine(LowerCase(ATrimmedLine)) then
    Exit;

  M := TRegEx.Match(ATrimmedLine, '^(class\s+)?(procedure|function|constructor|destructor)\s+(\w+)', [roIgnoreCase]);
  if M.Success then
  begin
    AKind := M.Groups[2].Value;
    AName := M.Groups[3].Value;
    Exit(True);
  end;

  M := TRegEx.Match(ATrimmedLine, '^(class\s+)?property\s+(\w+)', [roIgnoreCase]);
  if M.Success then
  begin
    AKind := 'property';
    AName := M.Groups[2].Value;
    Exit(True);
  end;

  M := TRegEx.Match(ATrimmedLine, '^(class\s+var\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*[^;]+;?\s*$');
  if M.Success then
  begin
    AKind := 'field';
    AName := M.Groups[2].Value;
    Exit(True);
  end;
end;

type
  TfrmClassBrowser = class(TForm)
  private
    FTree: TTreeView;
    FStatusLabel: TLabel;
    FFileName: string;
    procedure AnalyzeUnit;
    procedure TreeDblClick(Sender: TObject);
    procedure AddMemberClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmClassBrowser.Create(AOwner: TComponent);
var
  Top: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'Class Browser';
  ClientWidth := 460;
  ClientHeight := 560;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Class Browser', 'Classes, métodos, propriedades e campos da unit ativa');

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

  FTree.PopupMenu := TPopupMenu.Create(Self);
  FTree.PopupMenu.Items.Add(NewItem('Adicionar Membro...', 0, False, True, AddMemberClick, 0, ''));

  AnalyzeUnit;
end;

procedure TfrmClassBrowser.AnalyzeUnit;
var
  Editor: IOTASourceEditor;
  FullText: string;
  ClassRE: TRegEx;
  ClassMatch: TMatch;
  ClassNode, MemberNode: TTreeNode;
  ParentInfo, Caption: string;
  BodyText: string;
  BodyStartLine, LineNo, I: Integer;
  BodyLines: TArray<string>;
  Kind, Name: string;
  ClassCount: Integer;
begin
  Editor := GetActiveSourceEditor;
  if Editor = nil then
  begin
    FStatusLabel.Caption := 'Nenhum editor de código ativo.';
    Exit;
  end;
  FFileName := Editor.FileName;
  FullText := GetEditorText(Editor);

  ClassRE := TRegEx.Create('(\w+)\s*=\s*class(?!\s+of\b)\s*(\(([^)]*)\))?(.*?)\r?\n\s*end\s*;',
    [roIgnoreCase, roSingleLine]);

  ClassCount := 0;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    for ClassMatch in ClassRE.Matches(FullText) do
    begin
      Inc(ClassCount);
      ParentInfo := Trim(ClassMatch.Groups[3].Value);
      if ParentInfo <> '' then
        Caption := Format('%s (%s)', [ClassMatch.Groups[1].Value, ParentInfo])
      else
        Caption := ClassMatch.Groups[1].Value;

      ClassNode := FTree.Items.AddObject(nil, Caption,
        TObject(LineNumberAtPos(FullText, ClassMatch.Index)));

      BodyText := ClassMatch.Groups[4].Value;
      BodyStartLine := LineNumberAtPos(FullText, ClassMatch.Groups[4].Index);
      BodyLines := BodyText.Replace(#13, '').Split([#10]);
      for I := 0 to High(BodyLines) do
      begin
        if ClassifyMember(Trim(BodyLines[I]), Kind, Name) then
        begin
          LineNo := BodyStartLine + I;
          MemberNode := FTree.Items.AddChildObject(ClassNode, Format('[%s] %s', [Kind, Name]), TObject(LineNo));
        end;
      end;
    end;
    FTree.FullExpand;
  finally
    FTree.Items.EndUpdate;
  end;

  if ClassCount = 0 then
    FStatusLabel.Caption := 'Nenhuma declaração de classe encontrada nesta unit.'
  else
    FStatusLabel.Caption := Format('%d classe(s) encontrada(s). Duplo-clique para navegar.', [ClassCount]);
end;

procedure TfrmClassBrowser.TreeDblClick(Sender: TObject);
var
  LineNo: Integer;
begin
  if (FTree.Selected = nil) or (FFileName = '') then
    Exit;
  LineNo := Integer(FTree.Selected.Data);
  if LineNo > 0 then
    GotoEditorLine(FFileName, LineNo);
end;

procedure TfrmClassBrowser.AddMemberClick(Sender: TObject);
begin
  ShowAddMember;
end;

procedure ShowClassBrowser;
var
  Form: TfrmClassBrowser;
begin
  Form := TfrmClassBrowser.Create(nil);
  Form.Show;
end;

end.
