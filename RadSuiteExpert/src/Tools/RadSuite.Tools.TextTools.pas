unit RadSuite.Tools.TextTools;

interface

procedure AlignCode;
procedure UntabifySelection;
procedure TabifySelection;
procedure ConvertCodeToString;
procedure SortSelectedLines;
procedure FormatUsesClause;
procedure FormatUsesClauseAlternate;

implementation

uses
  System.SysUtils, System.Classes, System.RegularExpressions, System.Math,
  Vcl.Dialogs,
  ToolsAPI,
  RadSuite.IDE.Utils;

const
  TabWidth = 2;

function SplitLinesKeepStyle(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13, '').Split([#10]);
end;

function JoinLines(const ALines: TArray<string>): string;
begin
  Result := string.Join(sLineBreak, ALines);
end;

{ Align Code: alinha o primeiro ":=" ou ":" de cada linha selecionada na
  mesma coluna, preenchendo com espaços antes do operador. }
procedure AlignCode;
var
  Selected: string;
  Lines: TArray<string>;
  I, MaxPrefix, OpPos, PadCount: Integer;
  Prefixes: TArray<Integer>;
  UseAssign: Boolean;
begin
  Selected := GetSelectedText(GetActiveSourceEditor);
  if Trim(Selected) = '' then
    Exit;
  Lines := SplitLinesKeepStyle(Selected);
  SetLength(Prefixes, Length(Lines));
  MaxPrefix := -1;
  for I := 0 to High(Lines) do
  begin
    OpPos := Pos(':=', Lines[I]);
    UseAssign := OpPos > 0;
    if not UseAssign then
      OpPos := Pos(':', Lines[I]);
    if OpPos > 0 then
    begin
      Prefixes[I] := OpPos - 1;
      MaxPrefix := Max(MaxPrefix, Prefixes[I]);
    end
    else
      Prefixes[I] := -1;
  end;
  if MaxPrefix < 0 then
    Exit;
  for I := 0 to High(Lines) do
    if Prefixes[I] >= 0 then
    begin
      PadCount := MaxPrefix - Prefixes[I];
      if PadCount > 0 then
        Lines[I] := Copy(Lines[I], 1, Prefixes[I]) + StringOfChar(' ', PadCount) +
          Copy(Lines[I], Prefixes[I] + 1, MaxInt);
    end;
  ReplaceSelectedText(JoinLines(Lines));
end;

procedure UntabifySelection;
var
  Selected: string;
begin
  Selected := GetSelectedText(GetActiveSourceEditor);
  if Selected = '' then
    Exit;
  ReplaceSelectedText(StringReplace(Selected, #9, StringOfChar(' ', TabWidth), [rfReplaceAll]));
end;

procedure TabifySelection;
var
  Selected: string;
  Lines: TArray<string>;
  I, SpaceCount: Integer;
  Line, LeadingSpaces, Rest: string;
begin
  Selected := GetSelectedText(GetActiveSourceEditor);
  if Selected = '' then
    Exit;
  Lines := SplitLinesKeepStyle(Selected);
  for I := 0 to High(Lines) do
  begin
    Line := Lines[I];
    SpaceCount := 0;
    while (SpaceCount < Length(Line)) and (Line[SpaceCount + 1] = ' ') do
      Inc(SpaceCount);
    if SpaceCount >= TabWidth then
    begin
      Rest := Copy(Line, SpaceCount + 1, MaxInt);
      LeadingSpaces := StringOfChar(#9, SpaceCount div TabWidth) + StringOfChar(' ', SpaceCount mod TabWidth);
      Lines[I] := LeadingSpaces + Rest;
    end;
  end;
  ReplaceSelectedText(JoinLines(Lines));
end;

procedure ConvertCodeToString;
var
  Selected: string;
  Lines: TArray<string>;
  I: Integer;
  Result_: string;
begin
  Selected := GetSelectedText(GetActiveSourceEditor);
  if Selected = '' then
    Exit;
  Lines := SplitLinesKeepStyle(Selected);
  Result_ := '';
  for I := 0 to High(Lines) do
  begin
    Result_ := Result_ + '  ''' + StringReplace(Lines[I], '''', '''''', [rfReplaceAll]) + '''';
    if I < High(Lines) then
      Result_ := Result_ + ' + sLineBreak +' + sLineBreak
    else
      Result_ := Result_ + ';';
  end;
  ReplaceSelectedText(Result_);
end;

procedure SortSelectedLines;
var
  Selected: string;
  Lines: TStringList;
begin
  Selected := GetSelectedText(GetActiveSourceEditor);
  if Trim(Selected) = '' then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := Selected;
    Lines.Sort;
    ReplaceSelectedText(Lines.Text.TrimRight([#13, #10]));
  finally
    Lines.Free;
  end;
end;

function ParseUsesUnitList(const AText: string): TArray<string>;
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

function RowColToCharPos(const Text: string; Row, Column: Integer): Integer;
var
  Lines: TArray<string>;
  I, Pos_: Integer;
begin
  Lines := Text.Replace(#13, '').Split([#10]);
  Pos_ := 0;
  for I := 0 to Row - 2 do
    if I <= High(Lines) then
      Pos_ := Pos_ + Length(Lines[I]) + 1;
  Result := Pos_ + Column;
end;

function FindNearestUsesClause(const FullText: string; CursorPos: Integer;
  out ClauseStart, ClauseEnd: Integer; out Units: TArray<string>): Boolean;
var
  RE: TRegEx;
  M: TMatch;
  BestDistance, Distance: Int64;
begin
  Result := False;
  BestDistance := High(Int64);
  RE := TRegEx.Create('\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
  for M in RE.Matches(FullText) do
  begin
    Distance := Abs(Int64(M.Index) - CursorPos);
    if Distance < BestDistance then
    begin
      BestDistance := Distance;
      ClauseStart := M.Index;
      ClauseEnd := M.Index + M.Length - 1;
      Units := ParseUsesUnitList(M.Groups[1].Value);
      Result := True;
    end;
  end;
end;

procedure ApplyUsesFormatting(MultiLine: Boolean);
var
  Editor: IOTASourceEditor;
  FullText, NewText, Replacement, Joined: string;
  CursorPos: Integer;
  ClauseStart, ClauseEnd, I: Integer;
  Units: TArray<string>;
begin
  Editor := GetActiveSourceEditor;
  if (Editor = nil) or (Editor.GetEditViewCount = 0) then
    Exit;
  FullText := GetEditorText(Editor);
  CursorPos := RowColToCharPos(FullText, Editor.EditViews[0].Position.Row, Editor.EditViews[0].Position.Column);
  if not FindNearestUsesClause(FullText, CursorPos, ClauseStart, ClauseEnd, Units) then
  begin
    MessageDlg('Não foi encontrada nenhuma cláusula uses neste ficheiro.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if Length(Units) = 0 then
    Exit;

  if MultiLine then
  begin
    Replacement := 'uses' + sLineBreak;
    for I := 0 to High(Units) do
    begin
      Replacement := Replacement + '  ' + Units[I];
      if I < High(Units) then
        Replacement := Replacement + ',' + sLineBreak
      else
        Replacement := Replacement + ';';
    end;
  end
  else
  begin
    Joined := string.Join(', ', Units);
    Replacement := 'uses ' + Joined + ';';
  end;

  NewText := Copy(FullText, 1, ClauseStart - 1) + Replacement + Copy(FullText, ClauseEnd + 1, MaxInt);
  SetEditorText(Editor, NewText);
end;

procedure FormatUsesClause;
begin
  ApplyUsesFormatting(True);
end;

procedure FormatUsesClauseAlternate;
begin
  ApplyUsesFormatting(False);
end;

end.
