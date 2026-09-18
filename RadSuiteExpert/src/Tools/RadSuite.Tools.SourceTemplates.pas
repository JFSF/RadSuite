unit RadSuite.Tools.SourceTemplates;

interface

procedure InsertUnitHeaderTemplate;
procedure InsertProcedureHeaderTemplate;

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions, System.Math,
  ToolsAPI,
  RadSuite.IDE.Utils;

function BuildUnitHeaderText(const UnitName: string): string;
begin
  Result :=
    '{------------------------------------------------------------------------------' + sLineBreak +
    '  Unit:        ' + UnitName + sLineBreak +
    '  Descrição:   ' + sLineBreak +
    '  Autor:       ' + sLineBreak +
    '  Data:        ' + FormatDateTime('yyyy-mm-dd', Now) + sLineBreak +
    '------------------------------------------------------------------------------}' + sLineBreak;
end;

function BuildProcedureHeaderText(const ProcName: string): string;
begin
  Result :=
    '{------------------------------------------------------------------------------' + sLineBreak +
    '  ' + ProcName + sLineBreak +
    sLineBreak +
    '  Parâmetros:' + sLineBreak +
    '  Retorno:' + sLineBreak +
    '------------------------------------------------------------------------------}' + sLineBreak;
end;

procedure InsertUnitHeaderTemplate;
var
  Editor: IOTASourceEditor;
  FullText, UnitName: string;
  M: TMatch;
begin
  Editor := GetActiveSourceEditor;
  if (Editor = nil) or (Editor.GetEditViewCount = 0) then
    Exit;
  FullText := GetEditorText(Editor);
  UnitName := ExtractFileName(Editor.FileName);
  M := TRegEx.Match(FullText, '\bunit\s+([\w\.]+)\s*;', [roIgnoreCase]);
  if M.Success then
    UnitName := M.Groups[1].Value;

  Editor.EditViews[0].Position.Move(1, 1);
  Editor.EditViews[0].Position.InsertText(BuildUnitHeaderText(UnitName));
  Editor.EditViews[0].Paint;
end;

procedure InsertProcedureHeaderTemplate;
var
  Editor: IOTASourceEditor;
  FullText: string;
  Lines: TArray<string>;
  Row, I: Integer;
  M: TMatch;
  ProcName: string;
begin
  Editor := GetActiveSourceEditor;
  if (Editor = nil) or (Editor.GetEditViewCount = 0) then
    Exit;
  FullText := GetEditorText(Editor);
  Row := Editor.EditViews[0].Position.Row;
  Lines := FullText.Replace(#13, '').Split([#10]);
  ProcName := '<nome do procedimento>';
  for I := Max(Row - 1, 0) to High(Lines) do
  begin
    M := TRegEx.Match(Lines[I], '\b(procedure|function|constructor|destructor)\s+([\w\.]+)', [roIgnoreCase]);
    if M.Success then
    begin
      ProcName := M.Groups[2].Value;
      Break;
    end;
  end;

  InsertTextAtCursor(BuildProcedureHeaderText(ProcName));
end;

end.
