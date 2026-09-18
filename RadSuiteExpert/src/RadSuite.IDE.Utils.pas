unit RadSuite.IDE.Utils;

interface

uses
  ToolsAPI;

function GetActiveSourceEditor: IOTASourceEditor;
function GetActiveProjectGroup: IOTAProjectGroup;
function GetActiveProject: IOTAProject;
function GetActiveProjectDir: string;
function GetProjectSourceFiles(const Project: IOTAProject): TArray<string>;
function GetEditorText(const Editor: IOTASourceEditor): string;
procedure SetEditorText(const Editor: IOTASourceEditor; const AText: string);
function GetSelectedText(const Editor: IOTASourceEditor): string;
procedure GotoEditorLine(const FileName: string; ALine: Integer; AColumn: Integer = 1);
procedure InsertTextAtCursor(const AText: string);
procedure ReplaceSelectedText(const AText: string);
function FindOpenSourceEditor(const FileName: string): IOTASourceEditor;
function GetFileContent(const FileName: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils;

function GetActiveSourceEditor: IOTASourceEditor;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  I: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Module := ModuleServices.CurrentModule;
  if Module = nil then
    Exit;
  for I := 0 to Module.GetModuleFileCount - 1 do
  begin
    Editor := Module.GetModuleFileEditor(I);
    if Supports(Editor, IOTASourceEditor, Result) then
      Exit;
  end;
end;

function GetActiveProjectGroup: IOTAProjectGroup;
var
  ModuleServices: IOTAModuleServices;
  I: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  for I := 0 to ModuleServices.ModuleCount - 1 do
    if Supports(ModuleServices.Modules[I], IOTAProjectGroup, Result) then
      Exit;
end;

function GetActiveProject: IOTAProject;
var
  ProjectGroup: IOTAProjectGroup;
begin
  Result := nil;
  ProjectGroup := GetActiveProjectGroup;
  if ProjectGroup <> nil then
    Result := ProjectGroup.ActiveProject;
end;

function GetActiveProjectDir: string;
var
  Project: IOTAProject;
begin
  Result := '';
  Project := GetActiveProject;
  if Project <> nil then
    Result := ExtractFilePath(Project.FileName);
end;

function GetProjectSourceFiles(const Project: IOTAProject): TArray<string>;
var
  I: Integer;
  List: TStringList;
begin
  List := TStringList.Create;
  try
    if Project <> nil then
      for I := 0 to Project.GetModuleCount - 1 do
        List.Add(Project.GetModule(I).FileName);
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function GetEditorText(const Editor: IOTASourceEditor): string;
const
  BufferSize = 8192;
var
  Reader: IOTAEditReader;
  Buffer: PAnsiChar;
  ReadCount: Integer;
  Position: Integer;
  RawText: AnsiString;
begin
  Result := '';
  if Editor = nil then
    Exit;
  Reader := Editor.CreateReader;
  RawText := '';
  GetMem(Buffer, BufferSize + 1);
  try
    Position := 0;
    repeat
      ReadCount := Reader.GetText(Position, Buffer, BufferSize);
      Buffer[ReadCount] := #0;
      RawText := RawText + PAnsiChar(Buffer);
      Inc(Position, ReadCount);
    until ReadCount < BufferSize;
  finally
    FreeMem(Buffer);
  end;
  Result := string(RawText);
end;

procedure SetEditorText(const Editor: IOTASourceEditor; const AText: string);
var
  Writer: IOTAEditWriter;
  RawText: AnsiString;
begin
  if Editor = nil then
    Exit;
  Writer := Editor.CreateUndoableWriter;
  Writer.DeleteTo(MaxInt);
  RawText := AnsiString(AText);
  Writer.Insert(PAnsiChar(RawText));
end;

function GetSelectedText(const Editor: IOTASourceEditor): string;
begin
  Result := '';
  try
    if (Editor <> nil) and (Editor.GetEditViewCount > 0) then
      Result := Editor.EditViews[0].Block.Text;
  except
    Result := '';
  end;
end;

procedure GotoEditorLine(const FileName: string; ALine: Integer; AColumn: Integer = 1);
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  I: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Module := ModuleServices.OpenModule(FileName);
  if Module = nil then
    Exit;
  Module.Show;
  SourceEditor := nil;
  for I := 0 to Module.GetModuleFileCount - 1 do
  begin
    Editor := Module.GetModuleFileEditor(I);
    if Supports(Editor, IOTASourceEditor, SourceEditor) then
      Break;
  end;
  if (SourceEditor <> nil) and (SourceEditor.GetEditViewCount > 0) then
  begin
    SourceEditor.Show;
    SourceEditor.EditViews[0].Position.GotoLine(ALine);
    if AColumn > 1 then
      SourceEditor.EditViews[0].Position.Move(ALine, AColumn)
    else
      SourceEditor.EditViews[0].Position.MoveBOL;
    SourceEditor.EditViews[0].Paint;
  end;
end;

procedure InsertTextAtCursor(const AText: string);
var
  Editor: IOTASourceEditor;
begin
  Editor := GetActiveSourceEditor;
  if (Editor = nil) or (Editor.GetEditViewCount = 0) then
    Exit;
  Editor.EditViews[0].Position.InsertText(AText);
  Editor.EditViews[0].Paint;
end;

procedure ReplaceSelectedText(const AText: string);
var
  Editor: IOTASourceEditor;
  Block: IOTAEditBlock;
begin
  Editor := GetActiveSourceEditor;
  if (Editor = nil) or (Editor.GetEditViewCount = 0) then
    Exit;
  try
    Block := Editor.EditViews[0].Block;
    if (Block <> nil) and (Block.Text <> '') then
      Block.Delete;
  except
    // sem seleção válida - insere apenas no cursor
  end;
  Editor.EditViews[0].Position.InsertText(AText);
  Editor.EditViews[0].Paint;
end;

function FindOpenSourceEditor(const FileName: string): IOTASourceEditor;
var
  ModuleServices: IOTAModuleServices;
  I, J: Integer;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SrcEditor: IOTASourceEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  for I := 0 to ModuleServices.ModuleCount - 1 do
  begin
    Module := ModuleServices.Modules[I];
    for J := 0 to Module.GetModuleFileCount - 1 do
    begin
      Editor := Module.GetModuleFileEditor(J);
      if Supports(Editor, IOTASourceEditor, SrcEditor) and SameText(SrcEditor.FileName, FileName) then
        Exit(SrcEditor);
    end;
  end;
end;

function GetFileContent(const FileName: string): string;
var
  Editor: IOTASourceEditor;
begin
  Editor := FindOpenSourceEditor(FileName);
  if Editor <> nil then
    Result := GetEditorText(Editor)
  else
    Result := TFile.ReadAllText(FileName);
end;

end.
