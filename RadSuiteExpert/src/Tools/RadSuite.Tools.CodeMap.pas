unit RadSuite.Tools.CodeMap;

interface

procedure ShowCodeMap;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI,
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.StrUtils, System.JSON, System.Generics.Collections,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

{
  Code Map & Checklist: gera uma página HTML offline (árvore de units do
  projeto ativo + métodos extraídos por análise estática + checklist de
  progresso/prioridade/notas, tudo guardado no navegador via localStorage)
  e mantém-na atualizada por vigilância periódica (polling) enquanto esta
  janela estiver aberta. Porta e funde, em Delphi, a lógica de dois scripts
  PowerShell equivalentes (mapa de código + checklist de código).

  Não é um parser Delphi completo: a extração de métodos é uma heurística
  textual (declarações function/procedure/constructor/destructor), tal
  como nas restantes ferramentas do RadSuite baseadas em regex.
}

const
  SQ = ''''; // representa um único carácter apóstrofo (')
  ReservedWords: array[0..8] of string = (
    'begin', 'var', 'const', 'type', 'asm', 'end', 'try', 'except', 'finally');

type
  TMethodInfo = record
    Name: string;
    Kind: string;
    Sig: string;
  end;

  TMethodArray = TArray<TMethodInfo>;

function IsReservedWord(const AWord: string): Boolean;
var
  W: string;
begin
  for W in ReservedWords do
    if SameText(W, AWord) then
      Exit(True);
  Result := False;
end;

function ToSlug(const AText: string): string;
var
  C: Char;
  SB: TStringBuilder;
  LastDash: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    LastDash := False;
    for C in LowerCase(AText) do
    begin
      if CharInSet(C, ['a'..'z', '0'..'9']) then
      begin
        SB.Append(C);
        LastDash := False;
      end
      else if not LastDash then
      begin
        SB.Append('-');
        LastDash := True;
      end;
    end;
    Result := SB.ToString.Trim(['-']);
    if Result = '' then
      Result := 'projeto';
  finally
    SB.Free;
  end;
end;

function EscapeHtml(const AText: string): string;
begin
  Result := AText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;');
end;

{ ---------------------------------------------------------------------------
  Extração de métodos por unit (porta da lógica PowerShell equivalente)
  --------------------------------------------------------------------------- }

function CleanUnitText(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, SQ + '(?:[^' + SQ + '\r\n]|' + SQ + SQ + ')*' + SQ, SQ + SQ);
  Result := TRegEx.Replace(Result, '\{.*?\}', '', [roSingleLine]);
  Result := TRegEx.Replace(Result, '\(\*.*?\*\)', '', [roSingleLine]);
  Result := TRegEx.Replace(Result, '//[^\r\n]*', '');
end;

procedure SplitUnitSections(const AText: string; out AIface, AImpl: string);
var
  MIface, MImpl: TMatch;
begin
  MIface := TRegEx.Match(AText, '^\s*interface\s*$', [roIgnoreCase, roMultiLine]);
  MImpl := TRegEx.Match(AText, '^\s*implementation\s*$', [roIgnoreCase, roMultiLine]);
  if MIface.Success and MImpl.Success and (MImpl.Index > MIface.Index) then
  begin
    AIface := Copy(AText, MIface.Index + MIface.Length, MImpl.Index - (MIface.Index + MIface.Length));
    AImpl := Copy(AText, MImpl.Index + MImpl.Length, MaxInt);
  end
  else if MImpl.Success then
  begin
    AIface := '';
    AImpl := Copy(AText, MImpl.Index + MImpl.Length, MaxInt);
  end
  else
  begin
    AIface := '';
    AImpl := AText;
  end;
end;

function GetTopLevelStatements(const AText: string): TArray<string>;
var
  List: TStringList;
  SB: TStringBuilder;
  Depth, I: Integer;
  Ch: Char;
begin
  List := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Depth := 0;
    for I := 1 to Length(AText) do
    begin
      Ch := AText[I];
      if Ch = '(' then Inc(Depth)
      else if Ch = ')' then Dec(Depth);
      if (Ch = ';') and (Depth <= 0) then
      begin
        List.Add(SB.ToString);
        SB.Clear;
      end
      else
        SB.Append(Ch);
    end;
    if SB.Length > 0 then
      List.Add(SB.ToString);
    Result := List.ToStringArray;
  finally
    SB.Free;
    List.Free;
  end;
end;

function GetLastDeclMatch(const AStatement: string; out AIsClassMethod: Boolean;
  out AKind, AName, AMemberName: string; out AMatchIndex: Integer): Boolean;
const
  ReDecl = '(class\s+)?(function|procedure|constructor|destructor)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(\.\s*([A-Za-z_][A-Za-z0-9_]*))?';
var
  RE: TRegEx;
  Matches: TMatchCollection;
  I: Integer;
  M: TMatch;
  Name_, Member: string;
begin
  Result := False;
  RE := TRegEx.Create(ReDecl, [roIgnoreCase]);
  Matches := RE.Matches(AStatement);
  for I := Matches.Count - 1 downto 0 do
  begin
    M := Matches[I];
    Name_ := M.Groups[3].Value;
    Member := M.Groups[5].Value;
    if IsReservedWord(Name_) then
      Continue;
    if (Member <> '') and IsReservedWord(Member) then
      Continue;
    AIsClassMethod := M.Groups[1].Success;
    AKind := LowerCase(M.Groups[2].Value);
    AName := Name_;
    AMemberName := Member;
    AMatchIndex := M.Index;
    Exit(True);
  end;
end;

function GetUnitMethods(const AFilePath: string): TMethodArray;
var
  RawText, Clean, Iface, Impl: string;
  List: TList<TMethodInfo>;
  Seen: TDictionary<string, Boolean>;

  procedure ProcessSection(const SectionText: string; SkipMemberImpl: Boolean);
  var
    Stmt: string;
    Statements: TArray<string>;
    IsClassMethod: Boolean;
    Kind, Name_, Member, Key, Sig: string;
    MatchIndex: Integer;
    Info: TMethodInfo;
  begin
    Statements := GetTopLevelStatements(SectionText);
    for Stmt in Statements do
    begin
      if not GetLastDeclMatch(Stmt, IsClassMethod, Kind, Name_, Member, MatchIndex) then
        Continue;
      if SkipMemberImpl and (Member <> '') then
        Continue;
      Key := LowerCase(Name_);
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      if IsClassMethod then
        Kind := 'class ' + Kind;
      Sig := Trim(TRegEx.Replace(Copy(Stmt, MatchIndex, MaxInt), '\s+', ' '));
      if (Sig = '') or (Sig[Length(Sig)] <> ';') then
        Sig := Sig + ';';
      Info.Name := Name_;
      Info.Kind := Kind;
      Info.Sig := Sig;
      List.Add(Info);
    end;
  end;

begin
  RawText := TFile.ReadAllText(AFilePath);
  Clean := CleanUnitText(RawText);
  SplitUnitSections(Clean, Iface, Impl);

  List := TList<TMethodInfo>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    ProcessSection(Iface, False);
    ProcessSection(Impl, True);
    Result := List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end;

function GetProjectRelativeUnitFiles(const AProject: IOTAProject; const AProjectDir: string): TArray<string>;
var
  List: TStringList;
  F, Rel: string;
begin
  List := TStringList.Create;
  try
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    for F in GetProjectSourceFiles(AProject) do
      if SameText(ExtractFileExt(F), '.pas') or SameText(ExtractFileExt(F), '.dpr') then
      begin
        Rel := F;
        if StartsText(AProjectDir, Rel) then
          Rel := Copy(Rel, Length(AProjectDir) + 1, MaxInt);
        Rel := StringReplace(Rel, '\', '/', [rfReplaceAll]);
        List.Add(Rel);
      end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Cache local da última lista de units (para o destaque de units "NOVAS")
  --------------------------------------------------------------------------- }

function GetCacheFilePath(const ASlug: string): string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'RadSuite'), 'CodeMap_' + ASlug + '.cache.txt');
end;

function LoadPreviousFiles(const ASlug: string): TStringList;
begin
  Result := TStringList.Create;
  if TFile.Exists(GetCacheFilePath(ASlug)) then
    Result.LoadFromFile(GetCacheFilePath(ASlug), TEncoding.UTF8);
end;

procedure SavePreviousFiles(const ASlug: string; const AFiles: TArray<string>);
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.AddStrings(AFiles);
    TDirectory.CreateDirectory(ExtractFilePath(GetCacheFilePath(ASlug)));
    List.SaveToFile(GetCacheFilePath(ASlug), TEncoding.UTF8);
  finally
    List.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Construção do JSON (FILES / METHODS / NEWFILES)
  --------------------------------------------------------------------------- }

function BuildFilesJson(const AFiles: TArray<string>): string;
var
  Arr: TJSONArray;
  F: string;
begin
  Arr := TJSONArray.Create;
  try
    for F in AFiles do
      Arr.Add(F);
    Result := Arr.ToJSON;
  finally
    Arr.Free;
  end;
end;

function BuildMethodsJson(AMethodsMap: TDictionary<string, TMethodArray>): string;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Key: string;
  M: TMethodInfo;
begin
  Root := TJSONObject.Create;
  try
    for Key in AMethodsMap.Keys do
    begin
      Arr := TJSONArray.Create;
      for M in AMethodsMap[Key] do
      begin
        Obj := TJSONObject.Create;
        Obj.AddPair('name', M.Name);
        Obj.AddPair('kind', M.Kind);
        Obj.AddPair('sig', M.Sig);
        Arr.AddElement(Obj);
      end;
      Root.AddPair(Key, Arr);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Construção da página HTML (CSS + marcação + script)
  --------------------------------------------------------------------------- }

function BuildHtmlPage(const AProjectName, AProjectDir: string; const AFiles: TArray<string>;
  AMethodsMap: TDictionary<string, TMethodArray>; const ANewFiles: TArray<string>;
  AFinalized: Boolean; const ASlug: string): string;
var
  SB: TStringBuilder;
  FilesJson, MethodsJson, NewFilesJson: string;
  ProjectNameHtml, ProjectDirHtml, GeneratedDate, StorageKey, FinalizedBanner: string;
begin
  FilesJson := BuildFilesJson(AFiles);
  MethodsJson := BuildMethodsJson(AMethodsMap);
  NewFilesJson := BuildFilesJson(ANewFiles);
  ProjectNameHtml := EscapeHtml(AProjectName);
  ProjectDirHtml := EscapeHtml(ExcludeTrailingPathDelimiter(AProjectDir));
  GeneratedDate := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  StorageKey := 'radsuite-codemap-' + ASlug;

  if AFinalized then
    FinalizedBanner := '  <div class="finalized-banner">PROJETO FINALIZADO em ' + GeneratedDate + '</div>'
  else
    FinalizedBanner := '';

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<!doctype html>');
    SB.AppendLine('<html lang="pt-PT">');
    SB.AppendLine('<head>');
    SB.AppendLine('<meta charset="utf-8">');
    SB.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">');
    SB.AppendLine('<title>' + ProjectNameHtml + ' — Mapa e Checklist de Código</title>');
    SB.AppendLine('<style>');
    SB.AppendLine(':root{--bg:#f6f7f4;--surface:#fff;--surface-2:#eef0eb;--border:#dcded7;--text:#1b1e1a;--text-dim:#63685f;--text-faint:#93978c;--accent:#23705f;--accent-strong:#17493d;--accent-soft:#e3ede9;--star:#b8860b;--pending:#96730f;--done-strike:#8b9088;--flag-compila:#2f6fed;--flag-sonar:#8b5cf6;--new-badge:#d9534f;--shadow:0 1px 2px rgba(20,24,18,.06),0 4px 14px rgba(20,24,18,.05);--radius:10px;--mono:Consolas,ui-monospace,Menlo,monospace;--sans:-apple-system,"Segoe UI",system-ui,sans-serif}');
    SB.AppendLine('@media (prefers-color-scheme:dark){:root{--bg:#14171a;--surface:#1b1f22;--surface-2:#202426;--border:#2c3134;--text:#e9ebe6;--text-dim:#9aa09a;--text-faint:#666c67;--accent:#4fb89b;--accent-strong:#7fd6bc;--accent-soft:#1e2f2b;--star:#e0b23c;--pending:#d7a53a;--done-strike:#565b56;--flag-compila:#6fa8ff;--flag-sonar:#c9a6ff}}');
    SB.AppendLine('html[data-theme="dark"]{--bg:#14171a;--surface:#1b1f22;--surface-2:#202426;--border:#2c3134;--text:#e9ebe6;--text-dim:#9aa09a;--text-faint:#666c67;--accent:#4fb89b;--accent-strong:#7fd6bc;--accent-soft:#1e2f2b;--star:#e0b23c;--pending:#d7a53a;--done-strike:#565b56;--flag-compila:#6fa8ff;--flag-sonar:#c9a6ff}');
    SB.AppendLine('html[data-theme="light"]{--bg:#f6f7f4;--surface:#fff;--surface-2:#eef0eb;--border:#dcded7;--text:#1b1e1a;--text-dim:#63685f;--text-faint:#93978c;--accent:#23705f;--accent-strong:#17493d;--accent-soft:#e3ede9;--star:#b8860b;--pending:#96730f;--done-strike:#8b9088;--flag-compila:#2f6fed;--flag-sonar:#8b5cf6}');
    SB.AppendLine('*{box-sizing:border-box}html,body{margin:0;padding:0}');
    SB.AppendLine('body{background:var(--bg);color:var(--text);font-family:var(--sans);-webkit-font-smoothing:antialiased}');
    SB.AppendLine('.shell{max-width:1240px;margin:0 auto;padding:2.2rem 1.5rem 4rem;display:grid;grid-template-columns:300px minmax(0,1fr);gap:2rem;align-items:start}');
    SB.AppendLine('@media (max-width:900px){.shell{grid-template-columns:1fr}}');
    SB.AppendLine('.finalized-banner{grid-column:1/-1;display:flex;align-items:center;gap:.6rem;background:var(--accent-soft);color:var(--accent-strong);border:1px solid var(--accent);border-radius:var(--radius);padding:.7rem 1rem;font-size:.88rem;font-weight:700}');
    SB.AppendLine('.page-head{grid-column:1/-1;display:flex;justify-content:space-between;align-items:flex-end;gap:1.5rem;flex-wrap:wrap;border-bottom:1px solid var(--border);padding-bottom:1.2rem;margin-bottom:.3rem}');
    SB.AppendLine('.page-head h1{font-size:1.55rem;font-weight:700;letter-spacing:-.01em;margin:0 0 .3rem}');
    SB.AppendLine('.eyebrow{font-family:var(--mono);font-size:.7rem;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);display:block;margin-bottom:.4rem}');
    SB.AppendLine('.page-head p.sub{margin:0;color:var(--text-dim);font-size:.86rem;max-width:52ch}');
    SB.AppendLine('.head-right{display:flex;align-items:flex-end;gap:.6rem}');
    SB.AppendLine('.meta{text-align:right;font-family:var(--mono);font-size:.72rem;color:var(--text-faint);line-height:1.55}');
    SB.AppendLine('.iconbtn{background:var(--surface);border:1px solid var(--border);color:var(--text-dim);border-radius:8px;width:32px;height:32px;cursor:pointer;font-size:.95rem;display:flex;align-items:center;justify-content:center;flex-shrink:0}');
    SB.AppendLine('.iconbtn:hover{border-color:var(--accent);color:var(--accent)}');
    SB.AppendLine('.iconbtn.active{background:var(--accent);border-color:var(--accent);color:#fff}');
    SB.AppendLine('.sidebar{position:sticky;top:1.3rem;display:flex;flex-direction:column;gap:.9rem;max-height:calc(100vh - 2.6rem);overflow-y:auto;padding-right:2px}');
    SB.AppendLine('.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:1rem 1.15rem;box-shadow:var(--shadow)}');
    SB.AppendLine('.bigpct{font-family:var(--mono);font-size:1.7rem;font-weight:700;line-height:1}');
    SB.AppendLine('.bigpct-label{color:var(--text-dim);font-size:.78rem;margin:.15rem 0 .6rem}');
    SB.AppendLine('.barouter{height:7px;border-radius:4px;background:var(--surface-2);overflow:hidden}');
    SB.AppendLine('.barouter>span{display:block;height:100%;background:var(--accent)}');
    SB.AppendLine('.stat-row{display:flex;justify-content:space-between;align-items:baseline;font-family:var(--mono);font-size:.76rem;color:var(--text-dim);padding:.18rem 0}');
    SB.AppendLine('.stat-row b{color:var(--text);font-variant-numeric:tabular-nums;font-size:.86rem}');
    SB.AppendLine('.layer-bar-row{display:flex;align-items:center;gap:.5rem;font-size:.7rem;font-family:var(--mono);color:var(--text-dim);margin-top:.3rem}');
    SB.AppendLine('.layer-bar-row .lname{width:88px;flex-shrink:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}');
    SB.AppendLine('.layer-bar-row .ltrack{flex:1;height:5px;border-radius:3px;background:var(--surface-2);overflow:hidden}');
    SB.AppendLine('.layer-bar-row .ltrack>span{display:block;height:100%;background:var(--accent)}');
    SB.AppendLine('.layer-bar-row .lfrac{flex-shrink:0;color:var(--text-faint);width:34px;text-align:right}');
    SB.AppendLine('.search-box{display:flex;align-items:center;gap:.5rem;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:.5rem .7rem;box-shadow:var(--shadow)}');
    SB.AppendLine('.search-box input{border:none;outline:none;background:transparent;color:var(--text);font-family:var(--sans);font-size:.86rem;width:100%}');
    SB.AppendLine('.search-box input::placeholder{color:var(--text-faint)}');
    SB.AppendLine('.search-hint{font-family:var(--mono);font-size:.65rem;color:var(--text-faint);border:1px solid var(--border);border-radius:4px;padding:.03rem .3rem}');
    SB.AppendLine('.chip-row{display:flex;flex-wrap:wrap;gap:.3rem}');
    SB.AppendLine('button.tag{font-family:var(--mono);font-size:.66rem;padding:.22rem .5rem;border-radius:999px;border:1px solid var(--border);background:var(--surface-2);color:var(--text-dim);cursor:pointer}');
    SB.AppendLine('button.tag.active{background:var(--accent);border-color:var(--accent);color:#fff}');
    SB.AppendLine('.toggle-row{display:flex;align-items:center;gap:.45rem;font-size:.76rem;color:var(--text-dim)}');
    SB.AppendLine('.toggle-row input{cursor:pointer}');
    SB.AppendLine('.action-row{display:flex;gap:.45rem}');
    SB.AppendLine('button.chip{flex:1;background:var(--surface);border:1px solid var(--border);color:var(--text-dim);border-radius:var(--radius);padding:.45rem .55rem;font-family:var(--sans);font-size:.74rem;cursor:pointer}');
    SB.AppendLine('button.chip:hover{border-color:var(--accent);color:var(--accent)}');
    SB.AppendLine('button.chip.warn:hover{border-color:#b8452f;color:#b8452f}');
    SB.AppendLine('input#importFile{display:none}');
    SB.AppendLine('nav.groupnav{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);box-shadow:var(--shadow);padding:.4rem;max-height:26vh;overflow-y:auto}');
    SB.AppendLine('nav.groupnav a{display:block;padding:.32rem .55rem;border-radius:6px;text-decoration:none;color:var(--text-dim);font-family:var(--mono);font-size:.68rem;cursor:pointer}');
    SB.AppendLine('nav.groupnav a:hover{background:var(--surface-2);color:var(--text)}');
    SB.AppendLine('nav.groupnav a.complete{color:var(--accent)}');
    SB.AppendLine('.vendor-note{font-size:.72rem;color:var(--text-faint);line-height:1.5;padding:0 .1rem}');
    SB.AppendLine('main{min-width:0}');
    SB.AppendLine('.dir{margin-bottom:.05rem}');
    SB.AppendLine('.dir-head{display:flex;align-items:center;gap:.45rem;padding:.36rem .45rem;border-radius:6px;cursor:pointer;font-family:var(--mono);font-size:.82rem;color:var(--text)}');
    SB.AppendLine('.dir-head:hover{background:var(--surface-2)}');
    SB.AppendLine('.dir-head .caret{width:1em;flex-shrink:0;color:var(--text-faint)}');
    SB.AppendLine('.dir.collapsed>.dir-children{display:none}');
    SB.AppendLine('.dir-head .dname{color:var(--accent-strong);font-weight:600}');
    SB.AppendLine('.dir-head .dcount{margin-left:auto;font-size:.66rem;color:var(--text-faint);flex-shrink:0}');
    SB.AppendLine('.dir-children{padding-left:1.2rem;border-left:1px solid var(--border);margin-left:.6rem}');
    SB.AppendLine('.file-wrap{border-bottom:1px solid transparent}');
    SB.AppendLine('.row{display:flex;align-items:flex-start;gap:.5rem;padding:.42rem .4rem;border-radius:6px}');
    SB.AppendLine('.row:hover{background:var(--surface-2)}');
    SB.AppendLine('.row .rowmain{display:flex;align-items:center;gap:.5rem;flex:1;min-width:0;cursor:pointer}');
    SB.AppendLine('.row input.donecb{width:16px;height:16px;flex-shrink:0;cursor:pointer;accent-color:var(--accent);margin-top:1px}');
    SB.AppendLine('.row input.donecb.pending{accent-color:var(--pending);cursor:default}');
    SB.AppendLine('.fname{font-family:var(--mono);font-size:.82rem;color:var(--text);overflow-wrap:anywhere}');
    SB.AppendLine('.fext{color:var(--accent)}');
    SB.AppendLine('.row.done .fname{color:var(--done-strike);text-decoration:line-through}');
    SB.AppendLine('.newbadge{font-family:var(--mono);font-size:.6rem;font-weight:700;color:#fff;background:var(--new-badge);border-radius:999px;padding:.05rem .4rem;flex-shrink:0}');
    SB.AppendLine('.starbtn{background:none;border:none;cursor:pointer;font-size:.9rem;padding:1px;color:var(--text-faint);flex-shrink:0}');
    SB.AppendLine('.starbtn.on{color:var(--star)}');
    SB.AppendLine('.flagchk{display:inline-flex;align-items:center;gap:.2rem;font-family:var(--mono);font-size:.64rem;color:var(--text-faint);cursor:pointer;user-select:none;flex-shrink:0}');
    SB.AppendLine('.flagchk input{cursor:pointer}');
    SB.AppendLine('.flagchk input.compila:checked{accent-color:var(--flag-compila)}');
    SB.AppendLine('.flagchk input.sonar:checked{accent-color:var(--flag-sonar)}');
    SB.AppendLine('.notebtn{background:none;border:none;cursor:pointer;color:var(--text-faint);flex-shrink:0;font-size:.85rem;padding:1px}');
    SB.AppendLine('.notebtn.has,.notebtn:hover{color:var(--accent)}');
    SB.AppendLine('.noterow{display:none;padding:.2rem .1rem .5rem 1.7rem}');
    SB.AppendLine('.noterow.open{display:block}');
    SB.AppendLine('.noterow textarea{width:100%;min-height:42px;resize:vertical;font-family:var(--sans);font-size:.78rem;background:var(--surface-2);border:1px solid var(--border);border-radius:6px;padding:.4rem .55rem;color:var(--text);outline:none}');
    SB.AppendLine('.methodsbtn{display:flex;align-items:center;gap:.25rem;background:none;cursor:pointer;border:1px solid var(--border);border-radius:999px;color:var(--text-faint);font-family:var(--mono);font-size:.64rem;padding:.08rem .45rem;flex-shrink:0;margin-left:auto}');
    SB.AppendLine('.methodsbtn.complete{color:var(--accent);border-color:var(--accent)}');
    SB.AppendLine('.methodsbtn.open{background:var(--surface-2)}');
    SB.AppendLine('.methodsrow{display:none;padding:.15rem .1rem .55rem 1.7rem}');
    SB.AppendLine('.methodsrow.open{display:block}');
    SB.AppendLine('.methodlist{list-style:none;margin:0;padding:0;border-left:2px solid var(--border)}');
    SB.AppendLine('.methoditem{display:flex;align-items:flex-start;gap:.5rem;padding:.26rem 0 .26rem .7rem}');
    SB.AppendLine('.methoditem input.donecb{width:14px;height:14px;margin-top:2px}');
    SB.AppendLine('.methoditem.done .msig{color:var(--done-strike);text-decoration:line-through}');
    SB.AppendLine('.mkind{font-family:var(--mono);font-size:.6rem;color:var(--text-faint);flex-shrink:0;padding-top:.15rem;min-width:74px}');
    SB.AppendLine('.msig{font-family:var(--mono);font-size:.76rem;color:var(--text);overflow-wrap:anywhere}');
    SB.AppendLine('.empty-state{color:var(--text-faint);font-size:.82rem;padding:2rem .5rem;text-align:center;font-family:var(--mono)}');
    SB.AppendLine('footer.page-foot{grid-column:1/-1;margin-top:.8rem;padding-top:1rem;border-top:1px solid var(--border);font-size:.74rem;color:var(--text-faint);display:flex;justify-content:space-between;flex-wrap:wrap;gap:.4rem}');
    SB.AppendLine('.toast{position:fixed;bottom:1.1rem;left:50%;transform:translateX(-50%) translateY(10px);opacity:0;background:var(--accent-strong);color:#fff;font-size:.8rem;padding:.5rem .9rem;border-radius:8px;box-shadow:var(--shadow);pointer-events:none;transition:opacity .18s,transform .18s;z-index:10}');
    SB.AppendLine('.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}');
    SB.AppendLine('.print-summary{display:none}');
    SB.AppendLine('@page{margin:14mm 12mm}');
    SB.AppendLine('@media print{');
    SB.AppendLine('  *{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important;box-shadow:none!important}');
    SB.AppendLine('  html{font-size:10.5pt}');
    SB.AppendLine('  :root,html[data-theme="dark"],html[data-theme="light"]{--bg:#fff;--surface:#fff;--surface-2:#f1f2ee;--border:#b9bcb2;--text:#000;--text-dim:#2c2f28;--text-faint:#52554d;--accent:#175a49;--accent-strong:#0f3f34;--accent-soft:#dcece5;--star:#7a5906;--pending:#6e520a;--done-strike:#63665e;--flag-compila:#1c4fb8;--flag-sonar:#5b21a6}');
    SB.AppendLine('  body{background:#fff;color:#000}');
    SB.AppendLine('  .sidebar,.iconbtn,.search-box,.chip-row,.action-row,.toggle-row,.methodsbtn,.toast,input#importFile{display:none!important}');
    SB.AppendLine('  .starbtn,.flagchk{pointer-events:none}');
    SB.AppendLine('  .print-summary{display:block;margin:0 0 1rem;padding:.5rem .8rem;border:1px solid #000;border-radius:6px;font-family:var(--mono);font-size:.76rem}');
    SB.AppendLine('  .shell{grid-template-columns:1fr;display:block;max-width:none;padding:0}');
    SB.AppendLine('  .page-head{border-bottom:2px solid #000}');
    SB.AppendLine('  .dir.collapsed>.dir-children{display:block!important}');
    SB.AppendLine('  .methodsrow{display:block!important;padding-left:1.7rem}');
    SB.AppendLine('  .noterow{display:none!important}');
    SB.AppendLine('  .noterow.has-content{display:block!important}');
    SB.AppendLine('  .file-wrap,.methoditem{page-break-inside:avoid}');
    SB.AppendLine('}');
    SB.AppendLine('</style>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');
    SB.AppendLine('<div class="shell">');
    if FinalizedBanner <> '' then
      SB.AppendLine(FinalizedBanner);
    SB.AppendLine('  <header class="page-head">');
    SB.AppendLine('    <div>');
    SB.AppendLine('      <span class="eyebrow">Mapa e checklist de código</span>');
    SB.AppendLine('      <h1>' + ProjectNameHtml + '</h1>');
    SB.AppendLine('      <p class="sub">Estrutura de units do projeto, métodos por unit e progresso de revisão — gerado pelo RadSuite Expert, guardado neste navegador.</p>');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="head-right">');
    SB.AppendLine('      <div class="meta">gerado ' + GeneratedDate + '<br>' + ProjectDirHtml + '</div>');
    SB.AppendLine('      <button class="iconbtn" id="autoReloadBtn" type="button" title="Recarregar automaticamente esta página">&#8635;</button>');
    SB.AppendLine('      <button class="iconbtn" id="themeToggle" type="button" title="Alternar tema">&#9680;</button>');
    SB.AppendLine('    </div>');
    SB.AppendLine('  </header>');
    SB.AppendLine('  <div class="print-summary" id="printSummary"></div>');
    SB.AppendLine('  <aside class="sidebar">');
    SB.AppendLine('    <div class="card">');
    SB.AppendLine('      <div class="bigpct" id="pct">0%</div>');
    SB.AppendLine('      <div class="bigpct-label" id="frac">0 / 0 ficheiros concluídos</div>');
    SB.AppendLine('      <div class="barouter"><span id="mainbar" style="width:0%"></span></div>');
    SB.AppendLine('      <div id="layerBars"></div>');
    SB.AppendLine('      <div class="stat-row" style="margin-top:.7rem;padding-top:.6rem;border-top:1px solid var(--border)"><span>Métodos revistos</span><b id="mstat">0 / 0</b></div>');
    SB.AppendLine('      <div class="stat-row"><span>Ficheiros · Compila</span><b id="statFilesCompila">0/0</b></div>');
    SB.AppendLine('      <div class="stat-row"><span>Ficheiros · Sonar</span><b id="statFilesSonar">0/0</b></div>');
    SB.AppendLine('      <div class="stat-row"><span>Métodos · Compila</span><b id="statMethodsCompila">0/0</b></div>');
    SB.AppendLine('      <div class="stat-row"><span>Métodos · Sonar</span><b id="statMethodsSonar">0/0</b></div>');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="search-box">');
    SB.AppendLine('      <span>&#128269;</span>');
    SB.AppendLine('      <input id="search" type="text" placeholder="Filtrar por pasta, ficheiro ou método..." autocomplete="off">');
    SB.AppendLine('      <span class="search-hint">/</span>');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="chip-row" id="layerChips"></div>');
    SB.AppendLine('    <label class="toggle-row"><input type="checkbox" id="starOnly"> mostrar só marcados com estrela</label>');
    SB.AppendLine('    <label class="toggle-row"><input type="checkbox" id="pendingOnly"> mostrar só por concluir</label>');
    SB.AppendLine('    <div class="action-row"><button class="chip" id="printBtn" type="button">Imprimir</button></div>');
    SB.AppendLine('    <div class="action-row">');
    SB.AppendLine('      <button class="chip" id="expandAll" type="button">Expandir tudo</button>');
    SB.AppendLine('      <button class="chip" id="collapseAll" type="button">Colapsar tudo</button>');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="action-row">');
    SB.AppendLine('      <button class="chip" id="expandMethods" type="button">Expandir métodos</button>');
    SB.AppendLine('      <button class="chip" id="collapseMethods" type="button">Colapsar métodos</button>');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="action-row">');
    SB.AppendLine('      <button class="chip" id="exportJson" type="button">Exportar JSON</button>');
    SB.AppendLine('      <button class="chip" id="importJson" type="button">Importar</button>');
    SB.AppendLine('      <input type="file" id="importFile" accept="application/json">');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="action-row">');
    SB.AppendLine('      <button class="chip" id="exportMd" type="button">Markdown</button>');
    SB.AppendLine('      <button class="chip" id="exportCsv" type="button">CSV</button>');
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="action-row"><button class="chip warn" id="resetProgress" type="button">Reiniciar progresso</button></div>');
    SB.AppendLine('    <nav class="groupnav" id="groupnav"></nav>');
    SB.AppendLine('    <p class="vendor-note">As units apresentadas são as registadas no projeto ativo do Delphi (não é uma varredura de pastas).</p>');
    SB.AppendLine('    <p class="vendor-note">Os métodos de cada unit são extraídos automaticamente das declarações function/procedure/constructor/destructor — é uma heurística de análise estática, não um parser Delphi completo.</p>');
    SB.AppendLine('    <p class="vendor-note">As caixas C (Compila) e S (Sonar), a estrela, as notas e o progresso ficam guardados neste navegador (localStorage).</p>');
    SB.AppendLine('  </aside>');
    SB.AppendLine('  <main id="main"></main>');
    SB.AppendLine('  <footer class="page-foot">');
    SB.AppendLine('    <span>' + ProjectNameHtml + ' · ' + ProjectDirHtml + '</span>');
    SB.AppendLine('    <span id="footcount"></span>');
    SB.AppendLine('  </footer>');
    SB.AppendLine('</div>');
    SB.AppendLine('<div class="toast" id="toast"></div>');
    SB.AppendLine('<script>');
    SB.AppendLine('(function(){');
    SB.AppendLine('  var FILES = ' + FilesJson + ';');
    SB.AppendLine('  var METHODS = ' + MethodsJson + ';');
    SB.AppendLine('  var NEWFILES = ' + NewFilesJson + ';');
    SB.AppendLine('  var STORAGE_KEY = "' + StorageKey + '";');
    SB.AppendLine('  var THEME_KEY = "radsuite-codemap-theme";');
    SB.AppendLine('  var RELOAD_KEY = "' + StorageKey + '-autoreload";');
    SB.AppendLine('  function loadState(){ try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {}; } catch(e){ return {}; } }');
    SB.AppendLine('  function saveState(){ try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch(e){} }');
    SB.AppendLine('  var state = loadState();');
    SB.AppendLine('  function rec(p){ return state[p] || (state[p] = {}); }');
    SB.AppendLine('  var newSet = {};');
    SB.AppendLine('  NEWFILES.forEach(function(p){ newSet[p] = true; });');
    SB.AppendLine('  function methodsOf(p){ return METHODS[p] || []; }');
    SB.AppendLine('  function methodDone(p,n){ var r = state[p]; return !!(r && r.m && r.m[n]); }');
    SB.AppendLine('  function setMethodDone(p,n,v){ var r = rec(p); if(!r.m) r.m={}; r.m[n]=v; saveState(); }');
    SB.AppendLine('  function methodFlag(p,n,k){ var r = state[p]; return !!(r && r[k] && r[k][n]); }');
    SB.AppendLine('  function setMethodFlag(p,n,k,v){ var r = rec(p); if(!r[k]) r[k]={}; r[k][n]=v; saveState(); }');
    SB.AppendLine('  function methodCounts(p){ var l = methodsOf(p), d=0; l.forEach(function(m){ if(methodDone(p,m.name)) d++; }); return {done:d,total:l.length}; }');
    SB.AppendLine('  function makeFlag(label,title,kind,checked,onChange){');
    SB.AppendLine('    var lab=document.createElement("label"); lab.className="flagchk"; lab.title=title;');
    SB.AppendLine('    var inp=document.createElement("input"); inp.type="checkbox"; inp.className=kind;');
    SB.AppendLine('    inp.checked=checked;');
    SB.AppendLine('    inp.addEventListener("change",function(){ onChange(inp.checked); });');
    SB.AppendLine('    var sp=document.createElement("span"); sp.textContent=label;');
    SB.AppendLine('    lab.appendChild(inp); lab.appendChild(sp);');
    SB.AppendLine('    return lab;');
    SB.AppendLine('  }');
    SB.AppendLine('  function extOf(n){ var i=n.lastIndexOf("."); return i===-1?"":n.slice(i); }');
    SB.AppendLine('  function classify(p){ var idx=p.lastIndexOf("/"); if(idx===-1) return "Raiz"; var dir=p.slice(0,idx); var s=dir.lastIndexOf("/"); return s===-1?dir:dir.slice(s+1); }');
    SB.AppendLine('  function isFileDone(p){');
    SB.AppendLine('    var ms=methodsOf(p);');
    SB.AppendLine('    if(ms.length){ var mc=methodCounts(p); return mc.total>0 && mc.done===mc.total; }');
    SB.AppendLine('    var r=state[p];');
    SB.AppendLine('    return !!(r && r.done);');
    SB.AppendLine('  }');
    SB.AppendLine('  function buildTree(files){');
    SB.AppendLine('    var root={name:"",path:"",type:"dir",childrenMap:{},children:[]};');
    SB.AppendLine('    files.forEach(function(f){');
    SB.AppendLine('      var parts=f.split("/"); var node=root; var acc="";');
    SB.AppendLine('      for(var i=0;i<parts.length;i++){');
    SB.AppendLine('        var seg=parts[i]; acc=acc?acc+"/"+seg:seg;');
    SB.AppendLine('        var isFile=i===parts.length-1;');
    SB.AppendLine('        if(!node.childrenMap[seg]){');
    SB.AppendLine('          var n={name:seg,path:acc,type:isFile?"file":"dir",childrenMap:{},children:[]};');
    SB.AppendLine('          node.childrenMap[seg]=n; node.children.push(n);');
    SB.AppendLine('        }');
    SB.AppendLine('        node=node.childrenMap[seg];');
    SB.AppendLine('      }');
    SB.AppendLine('    });');
    SB.AppendLine('    sortTree(root);');
    SB.AppendLine('    return root;');
    SB.AppendLine('  }');
    SB.AppendLine('  function sortTree(n){');
    SB.AppendLine('    n.children.sort(function(a,b){ if(a.type!==b.type) return a.type==="dir"?-1:1; return a.name.localeCompare(b.name); });');
    SB.AppendLine('    n.children.forEach(function(c){ if(c.type==="dir") sortTree(c); });');
    SB.AppendLine('  }');
    SB.AppendLine('  function countTree(n){');
    SB.AppendLine('    var folders=0, files=0, done=0;');
    SB.AppendLine('    (function walk(x){');
    SB.AppendLine('      x.children.forEach(function(c){');
    SB.AppendLine('        if(c.type==="dir"){ folders++; walk(c); }');
    SB.AppendLine('        else { files++; if(isFileDone(c.path)) done++; }');
    SB.AppendLine('      });');
    SB.AppendLine('    })(n);');
    SB.AppendLine('    return {folders:folders, files:files, done:done};');
    SB.AppendLine('  }');
    SB.AppendLine('  var activeLayers={};');
    SB.AppendLine('  var starOnly=false, pendingOnly=false;');
    SB.AppendLine('  function matchesQuery(node,q){');
    SB.AppendLine('    if(node.type==="file"){');
    SB.AppendLine('      if(node.name.toLowerCase().indexOf(q)!==-1) return true;');
    SB.AppendLine('      var ms=methodsOf(node.path);');
    SB.AppendLine('      for(var i=0;i<ms.length;i++){');
    SB.AppendLine('        if(ms[i].name.toLowerCase().indexOf(q)!==-1 || ms[i].sig.toLowerCase().indexOf(q)!==-1) return true;');
    SB.AppendLine('      }');
    SB.AppendLine('      return false;');
    SB.AppendLine('    }');
    SB.AppendLine('    return node.name.toLowerCase().indexOf(q)!==-1;');
    SB.AppendLine('  }');
    SB.AppendLine('  function passesFilters(node){');
    SB.AppendLine('    if(node.type!=="file") return true;');
    SB.AppendLine('    if(starOnly && !(state[node.path] && state[node.path].star)) return false;');
    SB.AppendLine('    if(pendingOnly && isFileDone(node.path)) return false;');
    SB.AppendLine('    var lk=Object.keys(activeLayers);');
    SB.AppendLine('    if(lk.length && !activeLayers[classify(node.path)]) return false;');
    SB.AppendLine('    return true;');
    SB.AppendLine('  }');
    SB.AppendLine('  function nodeVisible(node,q){');
    SB.AppendLine('    if(node.type!=="file") return true;');
    SB.AppendLine('    if(q && !matchesQuery(node,q)) return false;');
    SB.AppendLine('    return passesFilters(node);');
    SB.AppendLine('  }');
    SB.AppendLine('  function filterTree(node,q){');
    SB.AppendLine('    if(q && node.type==="dir" && node.name.toLowerCase().indexOf(q)!==-1){');
    SB.AppendLine('      return node;');
    SB.AppendLine('    }');
    SB.AppendLine('    var kept=[];');
    SB.AppendLine('    node.children.forEach(function(c){');
    SB.AppendLine('      if(c.type==="dir"){ var fc=filterTree(c,q); if(fc.children && fc.children.length) kept.push(fc); else if(fc===c) kept.push(fc); }');
    SB.AppendLine('      else if(nodeVisible(c,q)) kept.push(c);');
    SB.AppendLine('    });');
    SB.AppendLine('    return {name:node.name,path:node.path,type:node.type,children:kept};');
    SB.AppendLine('  }');
    SB.AppendLine('  function toast(msg){');
    SB.AppendLine('    var t=document.getElementById("toast"); t.textContent=msg; t.classList.add("show");');
    SB.AppendLine('    clearTimeout(toast._h); toast._h=setTimeout(function(){ t.classList.remove("show"); },1600);');
    SB.AppendLine('  }');
    SB.AppendLine('  function renderFile(node){');
    SB.AppendLine('    var wrap=document.createElement("div"); wrap.className="file-wrap";');
    SB.AppendLine('    var row=document.createElement("div");');
    SB.AppendLine('    var r=rec(node.path);');
    SB.AppendLine('    var ms=methodsOf(node.path);');
    SB.AppendLine('    var hasMethods=ms.length>0;');
    SB.AppendLine('    if(hasMethods){ var mc0=methodCounts(node.path); r.done = mc0.total>0 && mc0.done===mc0.total; }');
    SB.AppendLine('    row.className="row"+(isFileDone(node.path)?" done":"");');
    SB.AppendLine('    var main2=document.createElement("label"); main2.className="rowmain";');
    SB.AppendLine('    var cb=document.createElement("input"); cb.type="checkbox"; cb.className="donecb";');
    SB.AppendLine('    cb.checked=isFileDone(node.path);');
    SB.AppendLine('    if(hasMethods){');
    SB.AppendLine('      cb.classList.toggle("pending", !cb.checked);');
    SB.AppendLine('      cb.title="Esta unit fica concluída quando todos os métodos estiverem marcados.";');
    SB.AppendLine('      cb.addEventListener("click",function(e){ e.preventDefault(); });');
    SB.AppendLine('    } else {');
    SB.AppendLine('      cb.addEventListener("change",function(){');
    SB.AppendLine('        r.done=cb.checked; r.ts=Date.now(); saveState();');
    SB.AppendLine('        row.classList.toggle("done",cb.checked);');
    SB.AppendLine('        render();');
    SB.AppendLine('      });');
    SB.AppendLine('    }');
    SB.AppendLine('    var ext=extOf(node.name); var base=node.name.slice(0,node.name.length-ext.length);');
    SB.AppendLine('    var nameSpan=document.createElement("span"); nameSpan.className="fname";');
    SB.AppendLine('    nameSpan.textContent=base;');
    SB.AppendLine('    var extSpan=document.createElement("span"); extSpan.className="fext"; extSpan.textContent=ext;');
    SB.AppendLine('    nameSpan.appendChild(extSpan);');
    SB.AppendLine('    main2.appendChild(cb); main2.appendChild(nameSpan);');
    SB.AppendLine('    if(newSet[node.path]){');
    SB.AppendLine('      var badge=document.createElement("span"); badge.className="newbadge"; badge.textContent="NOVO";');
    SB.AppendLine('      main2.appendChild(badge);');
    SB.AppendLine('    }');
    SB.AppendLine('    var star=document.createElement("button"); star.type="button";');
    SB.AppendLine('    star.className="starbtn"+(r.star?" on":""); star.title="Prioridade";');
    SB.AppendLine('    star.textContent=r.star?"★":"☆";');
    SB.AppendLine('    star.addEventListener("click",function(){');
    SB.AppendLine('      r.star=!r.star; saveState(); star.classList.toggle("on",r.star);');
    SB.AppendLine('      star.textContent=r.star?"★":"☆";');
    SB.AppendLine('      if(starOnly) render();');
    SB.AppendLine('    });');
    SB.AppendLine('    var flagC=makeFlag("C","Compila sem erros","compila",!!r.compila,function(v){ r.compila=v; saveState(); updateStats(); });');
    SB.AppendLine('    var flagS=makeFlag("S","SonarQube aprovado","sonar",!!r.sonar,function(v){ r.sonar=v; saveState(); updateStats(); });');
    SB.AppendLine('    var noteBtn=document.createElement("button"); noteBtn.type="button";');
    SB.AppendLine('    noteBtn.className="notebtn"+(r.note?" has":""); noteBtn.title="Nota";');
    SB.AppendLine('    noteBtn.textContent="✎";');
    SB.AppendLine('    row.appendChild(main2); row.appendChild(star); row.appendChild(flagC); row.appendChild(flagS);');
    SB.AppendLine('    var methodsRow=null, mbtn=null;');
    SB.AppendLine('    if(hasMethods){');
    SB.AppendLine('      var mc=methodCounts(node.path);');
    SB.AppendLine('      mbtn=document.createElement("button"); mbtn.type="button";');
    SB.AppendLine('      mbtn.className="methodsbtn"+(mc.done===mc.total?" complete":"");');
    SB.AppendLine('      mbtn.textContent=mc.done+"/"+mc.total;');
    SB.AppendLine('      methodsRow=document.createElement("div"); methodsRow.className="methodsrow";');
    SB.AppendLine('      var ul=document.createElement("ul"); ul.className="methodlist";');
    SB.AppendLine('      ms.forEach(function(mm){');
    SB.AppendLine('        var li=document.createElement("li");');
    SB.AppendLine('        li.className="methoditem"+(methodDone(node.path,mm.name)?" done":"");');
    SB.AppendLine('        var mcb=document.createElement("input"); mcb.type="checkbox"; mcb.className="donecb";');
    SB.AppendLine('        mcb.checked=methodDone(node.path,mm.name);');
    SB.AppendLine('        mcb.addEventListener("change",function(){');
    SB.AppendLine('          setMethodDone(node.path,mm.name,mcb.checked);');
    SB.AppendLine('          li.classList.toggle("done",mcb.checked);');
    SB.AppendLine('          var nc=methodCounts(node.path);');
    SB.AppendLine('          mbtn.classList.toggle("complete",nc.done===nc.total);');
    SB.AppendLine('          mbtn.textContent=nc.done+"/"+nc.total;');
    SB.AppendLine('          r.done = nc.total>0 && nc.done===nc.total; r.ts=Date.now(); saveState();');
    SB.AppendLine('          cb.checked=r.done; cb.classList.toggle("pending", !r.done);');
    SB.AppendLine('          row.classList.toggle("done", r.done);');
    SB.AppendLine('          render();');
    SB.AppendLine('        });');
    SB.AppendLine('        var mFlagC=makeFlag("C","Método compila","compila",methodFlag(node.path,mm.name,"mc"),function(v){ setMethodFlag(node.path,mm.name,"mc",v); updateStats(); });');
    SB.AppendLine('        var mFlagS=makeFlag("S","Método aprovado no Sonar","sonar",methodFlag(node.path,mm.name,"mq"),function(v){ setMethodFlag(node.path,mm.name,"mq",v); updateStats(); });');
    SB.AppendLine('        var mk=document.createElement("span"); mk.className="mkind"; mk.textContent=mm.kind;');
    SB.AppendLine('        var msgEl=document.createElement("span"); msgEl.className="msig"; msgEl.textContent=mm.sig;');
    SB.AppendLine('        li.appendChild(mcb); li.appendChild(mFlagC); li.appendChild(mFlagS); li.appendChild(mk); li.appendChild(msgEl);');
    SB.AppendLine('        ul.appendChild(li);');
    SB.AppendLine('      });');
    SB.AppendLine('      methodsRow.appendChild(ul);');
    SB.AppendLine('      mbtn.addEventListener("click",function(){ methodsRow.classList.toggle("open"); mbtn.classList.toggle("open"); });');
    SB.AppendLine('      row.appendChild(mbtn);');
    SB.AppendLine('    }');
    SB.AppendLine('    row.appendChild(noteBtn);');
    SB.AppendLine('    var noteRow=document.createElement("div");');
    SB.AppendLine('    noteRow.className="noterow"+(r.note?" has-content":"");');
    SB.AppendLine('    var ta=document.createElement("textarea"); ta.placeholder="Nota sobre este ficheiro...";');
    SB.AppendLine('    ta.value=r.note||"";');
    SB.AppendLine('    ta.addEventListener("input",function(){');
    SB.AppendLine('      r.note=ta.value; saveState();');
    SB.AppendLine('      noteBtn.classList.toggle("has", !!r.note);');
    SB.AppendLine('      noteRow.classList.toggle("has-content", !!r.note);');
    SB.AppendLine('    });');
    SB.AppendLine('    noteRow.appendChild(ta);');
    SB.AppendLine('    noteBtn.addEventListener("click",function(){');
    SB.AppendLine('      noteRow.classList.toggle("open");');
    SB.AppendLine('      if(noteRow.classList.contains("open")) ta.focus();');
    SB.AppendLine('    });');
    SB.AppendLine('    wrap.appendChild(row);');
    SB.AppendLine('    wrap.appendChild(noteRow);');
    SB.AppendLine('    if(methodsRow) wrap.appendChild(methodsRow);');
    SB.AppendLine('    return wrap;');
    SB.AppendLine('  }');
    SB.AppendLine('  function renderTree(node,container){');
    SB.AppendLine('    node.children.forEach(function(c){');
    SB.AppendLine('      if(c.type==="dir"){');
    SB.AppendLine('        var counts=countTree(c);');
    SB.AppendLine('        var dirEl=document.createElement("div"); dirEl.className="dir";');
    SB.AppendLine('        var head=document.createElement("div"); head.className="dir-head";');
    SB.AppendLine('        var caret=document.createElement("span"); caret.className="caret"; caret.textContent="▾";');
    SB.AppendLine('        var dname=document.createElement("span"); dname.className="dname"; dname.textContent=c.name+"/";');
    SB.AppendLine('        var dcount=document.createElement("span"); dcount.className="dcount";');
    SB.AppendLine('        dcount.textContent=counts.done+"/"+counts.files;');
    SB.AppendLine('        head.appendChild(caret); head.appendChild(dname); head.appendChild(dcount);');
    SB.AppendLine('        head.addEventListener("click",function(){');
    SB.AppendLine('          dirEl.classList.toggle("collapsed");');
    SB.AppendLine('          caret.textContent = dirEl.classList.contains("collapsed") ? "▸" : "▾";');
    SB.AppendLine('        });');
    SB.AppendLine('        var childrenWrap=document.createElement("div"); childrenWrap.className="dir-children";');
    SB.AppendLine('        renderTree(c,childrenWrap);');
    SB.AppendLine('        dirEl.appendChild(head); dirEl.appendChild(childrenWrap);');
    SB.AppendLine('        container.appendChild(dirEl);');
    SB.AppendLine('      } else {');
    SB.AppendLine('        container.appendChild(renderFile(c));');
    SB.AppendLine('      }');
    SB.AppendLine('    });');
    SB.AppendLine('  }');
    SB.AppendLine('  var fullTree = buildTree(FILES);');
    SB.AppendLine('  function renderLayerChips(){');
    SB.AppendLine('    var wrap=document.getElementById("layerChips"); wrap.innerHTML="";');
    SB.AppendLine('    var present={};');
    SB.AppendLine('    FILES.forEach(function(p){ present[classify(p)]=true; });');
    SB.AppendLine('    Object.keys(present).sort().forEach(function(l){');
    SB.AppendLine('      var b=document.createElement("button"); b.type="button";');
    SB.AppendLine('      b.className="tag"+(activeLayers[l]?" active":"");');
    SB.AppendLine('      b.textContent=l;');
    SB.AppendLine('      b.addEventListener("click",function(){');
    SB.AppendLine('        if(activeLayers[l]) delete activeLayers[l]; else activeLayers[l]=true;');
    SB.AppendLine('        render();');
    SB.AppendLine('      });');
    SB.AppendLine('      wrap.appendChild(b);');
    SB.AppendLine('    });');
    SB.AppendLine('  }');
    SB.AppendLine('  function renderLayerBars(){');
    SB.AppendLine('    var wrap=document.getElementById("layerBars"); wrap.innerHTML="";');
    SB.AppendLine('    var counts={};');
    SB.AppendLine('    FILES.forEach(function(p){');
    SB.AppendLine('      var l=classify(p); counts[l]=counts[l]||{done:0,total:0}; counts[l].total++;');
    SB.AppendLine('      if(isFileDone(p)) counts[l].done++;');
    SB.AppendLine('    });');
    SB.AppendLine('    Object.keys(counts).sort().forEach(function(l){');
    SB.AppendLine('      var c=counts[l]; var pct=c.total?Math.round(c.done/c.total*100):0;');
    SB.AppendLine('      var row=document.createElement("div"); row.className="layer-bar-row";');
    SB.AppendLine('      var nameS=document.createElement("span"); nameS.className="lname"; nameS.title=l; nameS.textContent=l;');
    SB.AppendLine('      var track=document.createElement("span"); track.className="ltrack";');
    SB.AppendLine('      var fill=document.createElement("span"); fill.style.width=pct+"%"; track.appendChild(fill);');
    SB.AppendLine('      var frac=document.createElement("span"); frac.className="lfrac"; frac.textContent=c.done+"/"+c.total;');
    SB.AppendLine('      row.appendChild(nameS); row.appendChild(track); row.appendChild(frac);');
    SB.AppendLine('      wrap.appendChild(row);');
    SB.AppendLine('    });');
    SB.AppendLine('  }');
    SB.AppendLine('  function globalStats(){');
    SB.AppendLine('    var totalFiles=FILES.length, doneFiles=0, filesCompila=0, filesSonar=0;');
    SB.AppendLine('    FILES.forEach(function(p){');
    SB.AppendLine('      if(isFileDone(p)) doneFiles++;');
    SB.AppendLine('      var r=state[p];');
    SB.AppendLine('      if(r && r.compila) filesCompila++;');
    SB.AppendLine('      if(r && r.sonar) filesSonar++;');
    SB.AppendLine('    });');
    SB.AppendLine('    var totalM=0, doneM=0, mCompila=0, mSonar=0;');
    SB.AppendLine('    Object.keys(METHODS).forEach(function(p){');
    SB.AppendLine('      METHODS[p].forEach(function(mm){');
    SB.AppendLine('        totalM++;');
    SB.AppendLine('        if(methodDone(p,mm.name)) doneM++;');
    SB.AppendLine('        if(methodFlag(p,mm.name,"mc")) mCompila++;');
    SB.AppendLine('        if(methodFlag(p,mm.name,"mq")) mSonar++;');
    SB.AppendLine('      });');
    SB.AppendLine('    });');
    SB.AppendLine('    return {totalFiles:totalFiles,doneFiles:doneFiles,filesCompila:filesCompila,filesSonar:filesSonar,');
    SB.AppendLine('      totalM:totalM,doneM:doneM,mCompila:mCompila,mSonar:mSonar};');
    SB.AppendLine('  }');
    SB.AppendLine('  function updateStats(){');
    SB.AppendLine('    var s=globalStats();');
    SB.AppendLine('    var pct = s.totalFiles ? Math.round(s.doneFiles/s.totalFiles*100) : 0;');
    SB.AppendLine('    document.getElementById("pct").textContent=pct+"%";');
    SB.AppendLine('    document.getElementById("frac").textContent=s.doneFiles+" / "+s.totalFiles+" ficheiros concluídos";');
    SB.AppendLine('    document.getElementById("mainbar").style.width=pct+"%";');
    SB.AppendLine('    document.getElementById("mstat").textContent=s.doneM+" / "+s.totalM;');
    SB.AppendLine('    document.getElementById("statFilesCompila").textContent=s.filesCompila+"/"+s.totalFiles;');
    SB.AppendLine('    document.getElementById("statFilesSonar").textContent=s.filesSonar+"/"+s.totalFiles;');
    SB.AppendLine('    document.getElementById("statMethodsCompila").textContent=s.mCompila+"/"+s.totalM;');
    SB.AppendLine('    document.getElementById("statMethodsSonar").textContent=s.mSonar+"/"+s.totalM;');
    SB.AppendLine('    document.getElementById("footcount").textContent=s.doneFiles+" de "+s.totalFiles+" ficheiros · "+s.doneM+" de "+s.totalM+" métodos";');
    SB.AppendLine('    updatePrintSummary(s);');
    SB.AppendLine('    renderLayerBars();');
    SB.AppendLine('    updateNav();');
    SB.AppendLine('  }');
    SB.AppendLine('  function updatePrintSummary(s){');
    SB.AppendLine('    var el=document.getElementById("printSummary"); if(!el) return;');
    SB.AppendLine('    s=s||globalStats();');
    SB.AppendLine('    el.textContent = s.doneFiles+"/"+s.totalFiles+" ficheiros concluídos, "+s.filesCompila+"/"+s.totalFiles+" compila, "+');
    SB.AppendLine('      s.filesSonar+"/"+s.totalFiles+" sonar — "+s.doneM+"/"+s.totalM+" métodos revistos — impresso em "+new Date().toLocaleString();');
    SB.AppendLine('  }');
    SB.AppendLine('  function updateNav(){');
    SB.AppendLine('    var nav=document.getElementById("groupnav"); nav.innerHTML="";');
    SB.AppendLine('    var dirs={};');
    SB.AppendLine('    FILES.forEach(function(p){ var idx=p.lastIndexOf("/"); var d=idx===-1?"(raiz)":p.slice(0,idx); (dirs[d]=dirs[d]||[]).push(p); });');
    SB.AppendLine('    Object.keys(dirs).sort().forEach(function(d){');
    SB.AppendLine('      var items=dirs[d]; var done=items.filter(isFileDone).length;');
    SB.AppendLine('      var a=document.createElement("a");');
    SB.AppendLine('      a.className = done===items.length ? "complete" : "";');
    SB.AppendLine('      a.textContent=d+" ("+done+"/"+items.length+")";');
    SB.AppendLine('      a.addEventListener("click",function(){');
    SB.AppendLine('        var target=d.split("/").pop()+"/";');
    SB.AppendLine('        var els=document.querySelectorAll(".dname");');
    SB.AppendLine('        for(var i=0;i<els.length;i++){');
    SB.AppendLine('          if(els[i].textContent===target){ els[i].scrollIntoView({block:"center"}); break; }');
    SB.AppendLine('        }');
    SB.AppendLine('      });');
    SB.AppendLine('      nav.appendChild(a);');
    SB.AppendLine('    });');
    SB.AppendLine('  }');
    SB.AppendLine('  function render(){');
    SB.AppendLine('    var main=document.getElementById("main"); main.innerHTML="";');
    SB.AppendLine('    var q=document.getElementById("search").value.trim().toLowerCase();');
    SB.AppendLine('    var tree=filterTree(fullTree,q);');
    SB.AppendLine('    if(!tree.children.length){');
    SB.AppendLine('      var empty=document.createElement("div"); empty.className="empty-state";');
    SB.AppendLine('      empty.textContent="Nenhum resultado para os filtros atuais.";');
    SB.AppendLine('      main.appendChild(empty);');
    SB.AppendLine('    } else {');
    SB.AppendLine('      renderTree(tree,main);');
    SB.AppendLine('    }');
    SB.AppendLine('    renderLayerChips();');
    SB.AppendLine('    updateStats();');
    SB.AppendLine('  }');
    SB.AppendLine('  document.getElementById("search").addEventListener("input",render);');
    SB.AppendLine('  document.getElementById("starOnly").addEventListener("change",function(e){ starOnly=e.target.checked; render(); });');
    SB.AppendLine('  document.getElementById("pendingOnly").addEventListener("change",function(e){ pendingOnly=e.target.checked; render(); });');
    SB.AppendLine('  document.getElementById("printBtn").addEventListener("click",function(){');
    SB.AppendLine('    document.getElementById("search").value=""; render();');
    SB.AppendLine('    document.querySelectorAll(".dir").forEach(function(d){ d.classList.remove("collapsed"); });');
    SB.AppendLine('    document.querySelectorAll(".methodsrow").forEach(function(r){ r.classList.add("open"); });');
    SB.AppendLine('    document.querySelectorAll(".methodsbtn").forEach(function(b){ b.classList.add("open"); });');
    SB.AppendLine('    updatePrintSummary();');
    SB.AppendLine('    setTimeout(function(){ window.print(); },50);');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("expandAll").addEventListener("click",function(){');
    SB.AppendLine('    document.querySelectorAll(".dir").forEach(function(d){ d.classList.remove("collapsed"); });');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("collapseAll").addEventListener("click",function(){');
    SB.AppendLine('    document.querySelectorAll(".dir").forEach(function(d){ d.classList.add("collapsed"); });');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("expandMethods").addEventListener("click",function(){');
    SB.AppendLine('    document.querySelectorAll(".methodsrow").forEach(function(r){ r.classList.add("open"); });');
    SB.AppendLine('    document.querySelectorAll(".methodsbtn").forEach(function(b){ b.classList.add("open"); });');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("collapseMethods").addEventListener("click",function(){');
    SB.AppendLine('    document.querySelectorAll(".methodsrow").forEach(function(r){ r.classList.remove("open"); });');
    SB.AppendLine('    document.querySelectorAll(".methodsbtn").forEach(function(b){ b.classList.remove("open"); });');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("resetProgress").addEventListener("click",function(){');
    SB.AppendLine('    if(!confirm("Reiniciar todo o progresso, notas e prioridades?")) return;');
    SB.AppendLine('    state={}; saveState(); render(); toast("Progresso reiniciado");');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("exportJson").addEventListener("click",function(){');
    SB.AppendLine('    var blob=new Blob([JSON.stringify({version:1,exportedAt:new Date().toISOString(),state:state},null,2)],{type:"application/json"});');
    SB.AppendLine('    var url=URL.createObjectURL(blob); var a=document.createElement("a");');
    SB.AppendLine('    a.href=url; a.download="codemap-progresso-"+new Date().toISOString().slice(0,10)+".json";');
    SB.AppendLine('    document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);');
    SB.AppendLine('    toast("Progresso exportado");');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("importJson").addEventListener("click",function(){ document.getElementById("importFile").click(); });');
    SB.AppendLine('  document.getElementById("importFile").addEventListener("change",function(e){');
    SB.AppendLine('    var file=e.target.files[0]; if(!file) return;');
    SB.AppendLine('    var reader=new FileReader();');
    SB.AppendLine('    reader.onload=function(){');
    SB.AppendLine('      try{');
    SB.AppendLine('        var data=JSON.parse(reader.result);');
    SB.AppendLine('        var incoming=data.state||data;');
    SB.AppendLine('        if(typeof incoming!=="object") throw new Error("formato inválido");');
    SB.AppendLine('        state=incoming; saveState(); render(); toast("Progresso importado");');
    SB.AppendLine('      } catch(err){ alert("Ficheiro inválido: "+err.message); }');
    SB.AppendLine('      e.target.value="";');
    SB.AppendLine('    };');
    SB.AppendLine('    reader.readAsText(file);');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("exportMd").addEventListener("click",function(){');
    SB.AppendLine('    var lines=["# Checklist de Código — "+document.title];');
    SB.AppendLine('    FILES.forEach(function(p){');
    SB.AppendLine('      var r=state[p]; var mark=isFileDone(p)?"x":" ";');
    SB.AppendLine('      var c=r&&r.compila?" [Compila]":""; var s=r&&r.sonar?" [Sonar]":""; var st=r&&r.star?" ★":"";');
    SB.AppendLine('      lines.push("- ["+mark+"] "+p+c+s+st);');
    SB.AppendLine('      methodsOf(p).forEach(function(mm){');
    SB.AppendLine('        var md=r&&r.m&&r.m[mm.name]?"x":" ";');
    SB.AppendLine('        lines.push("  - ["+md+"] `"+mm.sig+"`");');
    SB.AppendLine('      });');
    SB.AppendLine('    });');
    SB.AppendLine('    copyText(lines.join("\n"));');
    SB.AppendLine('  });');
    SB.AppendLine('  document.getElementById("exportCsv").addEventListener("click",function(){');
    SB.AppendLine('    var lines=["ficheiro,concluido,compila,sonar,estrela,metodos_total,metodos_concluidos"];');
    SB.AppendLine('    FILES.forEach(function(p){');
    SB.AppendLine('      var r=state[p]||{}; var mc=methodCounts(p);');
    SB.AppendLine('      lines.push([p,isFileDone(p),!!r.compila,!!r.sonar,!!r.star,mc.total,mc.done].join(","));');
    SB.AppendLine('    });');
    SB.AppendLine('    var blob=new Blob([lines.join("\n")],{type:"text/csv"});');
    SB.AppendLine('    var url=URL.createObjectURL(blob); var a=document.createElement("a");');
    SB.AppendLine('    a.href=url; a.download="codemap-"+new Date().toISOString().slice(0,10)+".csv";');
    SB.AppendLine('    document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);');
    SB.AppendLine('    toast("CSV exportado");');
    SB.AppendLine('  });');
    SB.AppendLine('  function copyText(text){');
    SB.AppendLine('    if(navigator.clipboard && navigator.clipboard.writeText){');
    SB.AppendLine('      navigator.clipboard.writeText(text).then(function(){ toast("Copiado"); }, function(){ fallbackCopy(text); });');
    SB.AppendLine('    } else { fallbackCopy(text); }');
    SB.AppendLine('  }');
    SB.AppendLine('  function fallbackCopy(text){');
    SB.AppendLine('    var ta=document.createElement("textarea"); ta.value=text; ta.style.position="fixed"; ta.style.opacity="0";');
    SB.AppendLine('    document.body.appendChild(ta); ta.select();');
    SB.AppendLine('    try{ document.execCommand("copy"); toast("Copiado"); } catch(e){ alert("Não foi possível copiar."); }');
    SB.AppendLine('    ta.remove();');
    SB.AppendLine('  }');
    SB.AppendLine('  function applyTheme(mode){');
    SB.AppendLine('    var root=document.documentElement;');
    SB.AppendLine('    if(mode==="system") delete root.dataset.theme; else root.dataset.theme=mode;');
    SB.AppendLine('    try{ localStorage.setItem(THEME_KEY,mode); }catch(e){}');
    SB.AppendLine('  }');
    SB.AppendLine('  var savedTheme="system";');
    SB.AppendLine('  try{ savedTheme=localStorage.getItem(THEME_KEY)||"system"; }catch(e){}');
    SB.AppendLine('  applyTheme(savedTheme);');
    SB.AppendLine('  document.getElementById("themeToggle").addEventListener("click",function(){');
    SB.AppendLine('    savedTheme = savedTheme==="light"?"dark":savedTheme==="dark"?"system":"light";');
    SB.AppendLine('    applyTheme(savedTheme);');
    SB.AppendLine('  });');
    SB.AppendLine('  var autoReloadOn=false;');
    SB.AppendLine('  try{ autoReloadOn = localStorage.getItem(RELOAD_KEY)==="1"; }catch(e){}');
    SB.AppendLine('  var reloadTimer=null;');
    SB.AppendLine('  function applyAutoReload(){');
    SB.AppendLine('    var btn=document.getElementById("autoReloadBtn");');
    SB.AppendLine('    btn.classList.toggle("active",autoReloadOn);');
    SB.AppendLine('    btn.title = autoReloadOn ? "Auto-atualizar: LIGADO (a página recarrega sozinha)" : "Auto-atualizar: desligado";');
    SB.AppendLine('    if(reloadTimer) clearInterval(reloadTimer);');
    SB.AppendLine('    if(autoReloadOn) reloadTimer=setInterval(function(){ location.reload(); },8000);');
    SB.AppendLine('  }');
    SB.AppendLine('  applyAutoReload();');
    SB.AppendLine('  document.getElementById("autoReloadBtn").addEventListener("click",function(){');
    SB.AppendLine('    autoReloadOn=!autoReloadOn;');
    SB.AppendLine('    try{ localStorage.setItem(RELOAD_KEY, autoReloadOn?"1":"0"); }catch(e){}');
    SB.AppendLine('    applyAutoReload();');
    SB.AppendLine('    toast(autoReloadOn?"Auto-atualizar ligado":"Auto-atualizar desligado");');
    SB.AppendLine('  });');
    SB.AppendLine('  document.addEventListener("keydown",function(e){');
    SB.AppendLine('    if(e.key==="/" && document.activeElement.tagName!=="INPUT" && document.activeElement.tagName!=="TEXTAREA"){');
    SB.AppendLine('      e.preventDefault(); document.getElementById("search").focus();');
    SB.AppendLine('    }');
    SB.AppendLine('  });');
    SB.AppendLine('  render();');
    SB.AppendLine('})();');
    SB.AppendLine('</script>');
    SB.AppendLine('</body>');
    SB.AppendLine('</html>');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Formulário / GUI
  --------------------------------------------------------------------------- }

type
  TfrmCodeMap = class(TForm)
  private
    FOutputEdit: TEdit;
    FOpenAfterCheck: TCheckBox;
    FIntervalEdit: TEdit;
    FWatchButton, FGenerateButton, FFinalizeButton, FReopenButton, FBrowseButton: TButton;
    FLogMemo: TMemo;
    FTimer: TTimer;
    FWatching: Boolean;
    FIsFinalized: Boolean;
    FLastSnapshot: string;
    procedure Log(const AMsg: string);
    procedure BrowseClick(Sender: TObject);
    procedure GenerateClick(Sender: TObject);
    procedure FinalizeClick(Sender: TObject);
    procedure ReopenClick(Sender: TObject);
    procedure WatchClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure GeneratePage(AFinalized, AAllowOpen: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  CodeMapForm: TfrmCodeMap;

constructor TfrmCodeMap.Create(AOwner: TComponent);
var
  Top: Integer;
  FieldsPanel, ButtonPanel, WatchPanel: TPanel;
  OutLabel, IntervalLabel: TLabel;
  Project: IOTAProject;
  ProjectDir, Slug: string;
begin
  inherited CreateNew(AOwner);
  Caption := 'Code Map & Checklist';
  ClientWidth := 640;
  ClientHeight := 480;
  BorderStyle := bsSizeable;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Code Map & Checklist',
    'Mapa e checklist de código do projeto ativo, com vigilância automática');

  FieldsPanel := TPanel.Create(Self);
  FieldsPanel.Parent := Self;
  FieldsPanel.Top := Top;
  FieldsPanel.Align := alTop;
  FieldsPanel.Height := 64;
  FieldsPanel.BevelOuter := bvNone;

  OutLabel := TLabel.Create(Self);
  OutLabel.Parent := FieldsPanel;
  OutLabel.Left := 12;
  OutLabel.Top := 4;
  OutLabel.Caption := 'Página HTML a gerar:';

  FOutputEdit := TEdit.Create(Self);
  FOutputEdit.Parent := FieldsPanel;
  FOutputEdit.Left := 12;
  FOutputEdit.Top := 22;
  FOutputEdit.Width := 520;

  FBrowseButton := TButton.Create(Self);
  FBrowseButton.Parent := FieldsPanel;
  FBrowseButton.Left := 540;
  FBrowseButton.Top := 20;
  FBrowseButton.Width := 80;
  FBrowseButton.Caption := 'Guardar...';
  FBrowseButton.OnClick := BrowseClick;

  FOpenAfterCheck := TCheckBox.Create(Self);
  FOpenAfterCheck.Parent := FieldsPanel;
  FOpenAfterCheck.Left := 12;
  FOpenAfterCheck.Top := 46;
  FOpenAfterCheck.Width := 260;
  FOpenAfterCheck.Caption := 'Abrir a página depois de gerar';
  FOpenAfterCheck.Checked := True;

  WatchPanel := TPanel.Create(Self);
  WatchPanel.Parent := Self;
  WatchPanel.Top := Top + 64;
  WatchPanel.Align := alTop;
  WatchPanel.Height := 40;
  WatchPanel.BevelOuter := bvNone;

  IntervalLabel := TLabel.Create(Self);
  IntervalLabel.Parent := WatchPanel;
  IntervalLabel.Left := 12;
  IntervalLabel.Top := 12;
  IntervalLabel.Caption := 'Intervalo (s):';

  FIntervalEdit := TEdit.Create(Self);
  FIntervalEdit.Parent := WatchPanel;
  FIntervalEdit.Left := 92;
  FIntervalEdit.Top := 8;
  FIntervalEdit.Width := 50;
  FIntervalEdit.Text := '5';

  FWatchButton := TButton.Create(Self);
  FWatchButton.Parent := WatchPanel;
  FWatchButton.Left := 156;
  FWatchButton.Top := 6;
  FWatchButton.Width := 180;
  FWatchButton.Caption := 'Iniciar vigilância';
  FWatchButton.OnClick := WatchClick;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  FGenerateButton := TButton.Create(Self);
  FGenerateButton.Parent := ButtonPanel;
  FGenerateButton.Left := 12;
  FGenerateButton.Top := 8;
  FGenerateButton.Width := 150;
  FGenerateButton.Caption := 'Gerar/Atualizar';
  FGenerateButton.OnClick := GenerateClick;

  FFinalizeButton := TButton.Create(Self);
  FFinalizeButton.Parent := ButtonPanel;
  FFinalizeButton.Left := 168;
  FFinalizeButton.Top := 8;
  FFinalizeButton.Width := 190;
  FFinalizeButton.Caption := 'Fechar como finalizado';
  FFinalizeButton.OnClick := FinalizeClick;

  FReopenButton := TButton.Create(Self);
  FReopenButton.Parent := ButtonPanel;
  FReopenButton.Left := 364;
  FReopenButton.Top := 8;
  FReopenButton.Width := 130;
  FReopenButton.Caption := 'Reabrir projeto';
  FReopenButton.OnClick := ReopenClick;

  FLogMemo := TMemo.Create(Self);
  FLogMemo.Parent := Self;
  FLogMemo.Align := alClient;
  FLogMemo.ReadOnly := True;
  FLogMemo.ScrollBars := ssVertical;
  FLogMemo.Font.Name := 'Consolas';
  FLogMemo.Font.Size := 9;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 5000;
  FTimer.OnTimer := TimerTick;

  Project := GetActiveProject;
  if Project <> nil then
  begin
    ProjectDir := GetActiveProjectDir;
    Slug := ToSlug(TPath.GetFileNameWithoutExtension(Project.FileName));
    FOutputEdit.Text := IncludeTrailingPathDelimiter(ProjectDir) + Slug + '-mapa-codigo.html';
  end
  else
    Log('Aviso: nenhum projeto ativo. Abra um projeto antes de gerar.');
end;

procedure TfrmCodeMap.Log(const AMsg: string);
begin
  FLogMemo.Lines.Add('[' + FormatDateTime('hh:nn:ss', Now) + '] ' + AMsg);
end;

procedure TfrmCodeMap.BrowseClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'Página HTML (*.html)|*.html';
    Dlg.FileName := FOutputEdit.Text;
    if Dlg.Execute then
      FOutputEdit.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmCodeMap.GenerateClick(Sender: TObject);
begin
  GeneratePage(FIsFinalized, True);
end;

procedure TfrmCodeMap.FinalizeClick(Sender: TObject);
begin
  FIsFinalized := True;
  GeneratePage(True, True);
end;

procedure TfrmCodeMap.ReopenClick(Sender: TObject);
begin
  FIsFinalized := False;
  GeneratePage(False, True);
end;

procedure TfrmCodeMap.WatchClick(Sender: TObject);
var
  Seconds: Integer;
begin
  if FWatching then
  begin
    FTimer.Enabled := False;
    FWatching := False;
    FWatchButton.Caption := 'Iniciar vigilância';
    Log('Vigilância parada.');
  end
  else
  begin
    if Trim(FOutputEdit.Text) = '' then
    begin
      MessageDlg('Indique primeiro o caminho da página a gerar.', mtWarning, [mbOK], 0);
      Exit;
    end;
    if not TryStrToInt(FIntervalEdit.Text, Seconds) or (Seconds < 1) then
      Seconds := 5;
    FIntervalEdit.Text := IntToStr(Seconds);
    FTimer.Interval := Seconds * 1000;
    GeneratePage(FIsFinalized, FOpenAfterCheck.Checked);
    FTimer.Enabled := True;
    FWatching := True;
    FWatchButton.Caption := 'Parar vigilância';
    Log(Format('Vigilância iniciada (a cada %ds).', [Seconds]));
  end;
end;

procedure TfrmCodeMap.TimerTick(Sender: TObject);
var
  Project: IOTAProject;
  ProjectDir: string;
  Files: TArray<string>;
  Snapshot: string;
begin
  Project := GetActiveProject;
  if Project = nil then
    Exit;
  ProjectDir := IncludeTrailingPathDelimiter(GetActiveProjectDir);
  Files := GetProjectRelativeUnitFiles(Project, ProjectDir);
  Snapshot := string.Join('|', Files);
  if Snapshot <> FLastSnapshot then
  begin
    Log('Alteração detetada nas units do projeto - a atualizar a página...');
    GeneratePage(FIsFinalized, False);
  end;
end;

procedure TfrmCodeMap.GeneratePage(AFinalized, AAllowOpen: Boolean);
var
  Project: IOTAProject;
  ProjectDir, ProjectName, Slug, Full: string;
  RelFiles: TArray<string>;
  MethodsMap: TDictionary<string, TMethodArray>;
  Methods: TMethodArray;
  PrevFiles: TStringList;
  NewFiles: TStringList;
  Html: string;
  F: string;
  FilesWithMethods: Integer;
begin
  if Trim(FOutputEdit.Text) = '' then
  begin
    MessageDlg('Indique o caminho da página a gerar.', mtWarning, [mbOK], 0);
    Exit;
  end;
  Project := GetActiveProject;
  if Project = nil then
  begin
    Log('Nenhum projeto ativo.');
    Exit;
  end;

  ProjectDir := IncludeTrailingPathDelimiter(GetActiveProjectDir);
  ProjectName := TPath.GetFileNameWithoutExtension(Project.FileName);
  Slug := ToSlug(ProjectName);

  RelFiles := GetProjectRelativeUnitFiles(Project, ProjectDir);
  if Length(RelFiles) = 0 then
  begin
    Log('O projeto ativo não tem units .pas/.dpr.');
    Exit;
  end;

  MethodsMap := TDictionary<string, TMethodArray>.Create;
  PrevFiles := LoadPreviousFiles(Slug);
  NewFiles := TStringList.Create;
  try
    FilesWithMethods := 0;
    for F in RelFiles do
    begin
      Full := ProjectDir + StringReplace(F, '/', '\', [rfReplaceAll]);
      try
        Methods := GetUnitMethods(Full);
      except
        Methods := nil;
      end;
      if Length(Methods) > 0 then
      begin
        MethodsMap.Add(F, Methods);
        Inc(FilesWithMethods);
      end;
      if PrevFiles.IndexOf(F) < 0 then
        NewFiles.Add(F);
    end;

    Html := BuildHtmlPage(ProjectName, ProjectDir, RelFiles, MethodsMap, NewFiles.ToStringArray, AFinalized, Slug);

    TDirectory.CreateDirectory(ExtractFilePath(FOutputEdit.Text));
    TFile.WriteAllText(FOutputEdit.Text, Html, TEncoding.UTF8);
    SavePreviousFiles(Slug, RelFiles);

    FLastSnapshot := string.Join('|', RelFiles);

    Log(Format('Página gerada: %s (%d ficheiros, %d com métodos)', [FOutputEdit.Text, Length(RelFiles), FilesWithMethods]));
    if NewFiles.Count > 0 then
      Log(Format('%d unit(s) nova(s) desde a última geração.', [NewFiles.Count]));

    if AAllowOpen and FOpenAfterCheck.Checked then
      ShellExecute(0, 'open', PChar(FOutputEdit.Text), nil, nil, SW_SHOWNORMAL);
  finally
    NewFiles.Free;
    PrevFiles.Free;
    MethodsMap.Free;
  end;
end;

procedure ShowCodeMap;
begin
  if CodeMapForm = nil then
    CodeMapForm := TfrmCodeMap.Create(Application);
  CodeMapForm.Show;
  CodeMapForm.BringToFront;
end;

initialization

finalization
  FreeAndNil(CodeMapForm);

end.
