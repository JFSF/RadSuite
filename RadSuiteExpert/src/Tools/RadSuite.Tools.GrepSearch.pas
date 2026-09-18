unit RadSuite.Tools.GrepSearch;

interface

procedure ShowGrepSearch;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  System.StrUtils,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs, Vcl.FileCtrl,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

type
  TGrepScope = (gsOpenFiles, gsProject, gsDirectory);

  TfrmGrepSearch = class(TForm)
  private
    FSearchEdit, FReplaceEdit, FDirEdit, FMaskEdit: TEdit;
    FRegexCheck, FCaseCheck, FWholeWordCheck: TCheckBox;
    FScopeRadio: TRadioGroup;
    FResultsList: TListView;
    FStatusLabel: TLabel;
    procedure BrowseDirClick(Sender: TObject);
    procedure SearchClick(Sender: TObject);
    procedure ReplaceClick(Sender: TObject);
    procedure ResultsDblClick(Sender: TObject);
    procedure ScopeChange(Sender: TObject);
    function CollectFiles: TArray<string>;
    function BuildRegex: TRegEx;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  GrepForm: TfrmGrepSearch;

function TfrmGrepSearch.BuildRegex: TRegEx;
var
  Pattern: string;
  Options: TRegexOptions;
begin
  if FRegexCheck.Checked then
    Pattern := FSearchEdit.Text
  else
    Pattern := TRegEx.Escape(FSearchEdit.Text);
  if FWholeWordCheck.Checked then
    Pattern := '\b' + Pattern + '\b';
  Options := [];
  if not FCaseCheck.Checked then
    Options := Options + [roIgnoreCase];
  Result := TRegEx.Create(Pattern, Options);
end;

function TfrmGrepSearch.CollectFiles: TArray<string>;
var
  List: TStringList;
  Project: IOTAProject;
  ModuleServices: IOTAModuleServices;
  I, J: Integer;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SrcEditor: IOTASourceEditor;
  Masks: TArray<string>;
  Mask: string;
  Files: TArray<string>;
  F: string;
begin
  List := TStringList.Create;
  try
    List.Sorted := True;
    List.Duplicates := dupIgnore;
    case TGrepScope(FScopeRadio.ItemIndex) of
      gsOpenFiles:
        if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
          for I := 0 to ModuleServices.ModuleCount - 1 do
          begin
            Module := ModuleServices.Modules[I];
            for J := 0 to Module.GetModuleFileCount - 1 do
            begin
              Editor := Module.GetModuleFileEditor(J);
              if Supports(Editor, IOTASourceEditor, SrcEditor) then
                List.Add(SrcEditor.FileName);
            end;
          end;
      gsProject:
        begin
          Project := GetActiveProject;
          if Project <> nil then
            for F in GetProjectSourceFiles(Project) do
              if MatchText(ExtractFileExt(F), ['.pas', '.dpr', '.dpk', '.inc']) then
                List.Add(F);
        end;
      gsDirectory:
        if TDirectory.Exists(FDirEdit.Text) then
        begin
          Masks := FMaskEdit.Text.Split([';']);
          for Mask in Masks do
            if Trim(Mask) <> '' then
            begin
              try
                Files := TDirectory.GetFiles(FDirEdit.Text, Trim(Mask), TSearchOption.soAllDirectories);
              except
                Files := [];
              end;
              for F in Files do
                List.Add(F);
            end;
        end;
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

constructor TfrmGrepSearch.Create(AOwner: TComponent);
var
  Top: Integer;
  SearchPanel, ScopePanel, OptionsPanel: TPanel;
  SearchLabel, ReplaceLabel, DirLabel, MaskLabel: TLabel;
  BrowseDirButton, SearchButton, ReplaceButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Grep Search & Replace';
  ClientWidth := 820;
  ClientHeight := 600;
  BorderStyle := bsSizeable;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Grep Search & Replace',
    'Procura (com regex opcional) em ficheiros abertos, no projeto ou numa pasta');

  SearchPanel := TPanel.Create(Self);
  SearchPanel.Parent := Self;
  SearchPanel.Top := Top;
  SearchPanel.Align := alTop;
  SearchPanel.Height := 74;
  SearchPanel.BevelOuter := bvNone;

  SearchLabel := TLabel.Create(Self);
  SearchLabel.Parent := SearchPanel;
  SearchLabel.Left := 12;
  SearchLabel.Top := 4;
  SearchLabel.Caption := 'Procurar:';

  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent := SearchPanel;
  FSearchEdit.Left := 12;
  FSearchEdit.Top := 20;
  FSearchEdit.Width := 380;

  ReplaceLabel := TLabel.Create(Self);
  ReplaceLabel.Parent := SearchPanel;
  ReplaceLabel.Left := 404;
  ReplaceLabel.Top := 4;
  ReplaceLabel.Caption := 'Substituir por:';

  FReplaceEdit := TEdit.Create(Self);
  FReplaceEdit.Parent := SearchPanel;
  FReplaceEdit.Left := 404;
  FReplaceEdit.Top := 20;
  FReplaceEdit.Width := 300;

  FRegexCheck := TCheckBox.Create(Self);
  FRegexCheck.Parent := SearchPanel;
  FRegexCheck.Left := 12;
  FRegexCheck.Top := 48;
  FRegexCheck.Width := 100;
  FRegexCheck.Caption := 'Regex';

  FCaseCheck := TCheckBox.Create(Self);
  FCaseCheck.Parent := SearchPanel;
  FCaseCheck.Left := 116;
  FCaseCheck.Top := 48;
  FCaseCheck.Width := 150;
  FCaseCheck.Caption := 'Sensível a maiúsculas';

  FWholeWordCheck := TCheckBox.Create(Self);
  FWholeWordCheck.Parent := SearchPanel;
  FWholeWordCheck.Left := 270;
  FWholeWordCheck.Top := 48;
  FWholeWordCheck.Width := 140;
  FWholeWordCheck.Caption := 'Palavra inteira';

  SearchButton := TButton.Create(Self);
  SearchButton.Parent := SearchPanel;
  SearchButton.Left := 720;
  SearchButton.Top := 18;
  SearchButton.Width := 90;
  SearchButton.Caption := 'Procurar';
  SearchButton.OnClick := SearchClick;

  ReplaceButton := TButton.Create(Self);
  ReplaceButton.Parent := SearchPanel;
  ReplaceButton.Left := 720;
  ReplaceButton.Top := 46;
  ReplaceButton.Width := 90;
  ReplaceButton.Caption := 'Substituir';
  ReplaceButton.OnClick := ReplaceClick;

  ScopePanel := TPanel.Create(Self);
  ScopePanel.Parent := Self;
  ScopePanel.Top := Top + 74;
  ScopePanel.Align := alTop;
  ScopePanel.Height := 34;
  ScopePanel.BevelOuter := bvNone;

  FScopeRadio := TRadioGroup.Create(Self);
  FScopeRadio.Parent := ScopePanel;
  FScopeRadio.Left := 12;
  FScopeRadio.Top := 0;
  FScopeRadio.Width := 380;
  FScopeRadio.Height := 34;
  FScopeRadio.Caption := '';
  FScopeRadio.Columns := 3;
  FScopeRadio.Items.Add('Ficheiros abertos');
  FScopeRadio.Items.Add('Projeto ativo');
  FScopeRadio.Items.Add('Pasta');
  FScopeRadio.ItemIndex := 0;
  FScopeRadio.OnClick := ScopeChange;

  OptionsPanel := TPanel.Create(Self);
  OptionsPanel.Parent := Self;
  OptionsPanel.Top := Top + 74 + 34;
  OptionsPanel.Align := alTop;
  OptionsPanel.Height := 34;
  OptionsPanel.BevelOuter := bvNone;

  DirLabel := TLabel.Create(Self);
  DirLabel.Parent := OptionsPanel;
  DirLabel.Left := 12;
  DirLabel.Top := 10;
  DirLabel.Caption := 'Pasta:';

  FDirEdit := TEdit.Create(Self);
  FDirEdit.Parent := OptionsPanel;
  FDirEdit.Left := 52;
  FDirEdit.Top := 6;
  FDirEdit.Width := 320;
  FDirEdit.Enabled := False;

  BrowseDirButton := TButton.Create(Self);
  BrowseDirButton.Parent := OptionsPanel;
  BrowseDirButton.Left := 378;
  BrowseDirButton.Top := 4;
  BrowseDirButton.Width := 30;
  BrowseDirButton.Caption := '...';
  BrowseDirButton.Enabled := False;
  BrowseDirButton.OnClick := BrowseDirClick;

  MaskLabel := TLabel.Create(Self);
  MaskLabel.Parent := OptionsPanel;
  MaskLabel.Left := 420;
  MaskLabel.Top := 10;
  MaskLabel.Caption := 'Máscara:';

  FMaskEdit := TEdit.Create(Self);
  FMaskEdit.Parent := OptionsPanel;
  FMaskEdit.Left := 480;
  FMaskEdit.Top := 6;
  FMaskEdit.Width := 200;
  FMaskEdit.Text := '*.pas;*.dfm;*.inc';
  FMaskEdit.Enabled := False;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.Caption := 'Pronto.';

  FResultsList := TListView.Create(Self);
  FResultsList.Parent := Self;
  FResultsList.Align := alClient;
  FResultsList.ViewStyle := vsReport;
  FResultsList.Checkboxes := True;
  FResultsList.RowSelect := True;
  FResultsList.GridLines := True;
  FResultsList.OnDblClick := ResultsDblClick;
  with FResultsList.Columns.Add do begin Caption := 'Ficheiro'; Width := 160; end;
  with FResultsList.Columns.Add do begin Caption := 'Linha'; Width := 60; end;
  with FResultsList.Columns.Add do begin Caption := 'Coluna'; Width := 60; end;
  with FResultsList.Columns.Add do begin Caption := 'Contexto'; Width := 380; end;
  with FResultsList.Columns.Add do begin Caption := 'Caminho completo'; Width := 0; end;
end;

procedure TfrmGrepSearch.ScopeChange(Sender: TObject);
var
  IsDir: Boolean;
begin
  IsDir := TGrepScope(FScopeRadio.ItemIndex) = gsDirectory;
  FDirEdit.Enabled := IsDir;
  FMaskEdit.Enabled := IsDir;
  if FDirEdit.Parent <> nil then
    for var I := 0 to FDirEdit.Parent.ControlCount - 1 do
      if FDirEdit.Parent.Controls[I] is TButton then
        FDirEdit.Parent.Controls[I].Enabled := IsDir;
end;

procedure TfrmGrepSearch.BrowseDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := FDirEdit.Text;
  if Dir = '' then
    Dir := GetActiveProjectDir;
  if SelectDirectory('Escolha a pasta a pesquisar', '', Dir) then
    FDirEdit.Text := Dir;
end;

procedure TfrmGrepSearch.SearchClick(Sender: TObject);
var
  RE: TRegEx;
  Files: TArray<string>;
  FileName, Content: string;
  Lines: TArray<string>;
  I: Integer;
  M: TMatch;
  Item: TListItem;
  TotalMatches: Integer;
begin
  if Trim(FSearchEdit.Text) = '' then
  begin
    MessageDlg('Indique o texto a procurar.', mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    RE := BuildRegex;
  except
    on E: Exception do
    begin
      MessageDlg('Expressão regular inválida: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;

  FResultsList.Items.BeginUpdate;
  try
    FResultsList.Items.Clear;
    TotalMatches := 0;
    Files := CollectFiles;
    for FileName in Files do
    begin
      try
        Content := GetFileContent(FileName);
      except
        Continue;
      end;
      Lines := Content.Replace(#13, '').Split([#10]);
      for I := 0 to High(Lines) do
        for M in RE.Matches(Lines[I]) do
        begin
          Item := FResultsList.Items.Add;
          Item.Caption := ExtractFileName(FileName);
          Item.SubItems.Add(IntToStr(I + 1));
          Item.SubItems.Add(IntToStr(M.Index));
          Item.SubItems.Add(Trim(Lines[I]));
          Item.SubItems.Add(FileName);
          Item.Checked := True;
          Inc(TotalMatches);
        end;
    end;
  finally
    FResultsList.Items.EndUpdate;
  end;
  FStatusLabel.Caption := Format('%d ocorrência(s) em %d ficheiro(s) pesquisado(s).', [TotalMatches, Length(Files)]);
end;

procedure TfrmGrepSearch.ReplaceClick(Sender: TObject);
var
  RE: TRegEx;
  Files: TStringList;
  I: Integer;
  FileName, Content, NewContent: string;
  Editor: IOTASourceEditor;
  AffectedCount: Integer;
begin
  if Trim(FSearchEdit.Text) = '' then
    Exit;
  Files := TStringList.Create;
  try
    Files.Sorted := True;
    Files.Duplicates := dupIgnore;
    for I := 0 to FResultsList.Items.Count - 1 do
      if FResultsList.Items[I].Checked then
        Files.Add(FResultsList.Items[I].SubItems[3]);

    if Files.Count = 0 then
    begin
      MessageDlg('Nenhum resultado marcado. Faça uma procura primeiro.', mtInformation, [mbOK], 0);
      Exit;
    end;

    if MessageDlg(Format(
        'Substituir todas as ocorrências de "%s" por "%s" em %d ficheiro(s)?' + sLineBreak +
        'Esta ação não pode ser desfeita.', [FSearchEdit.Text, FReplaceEdit.Text, Files.Count]),
        mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    RE := BuildRegex;
    AffectedCount := 0;
    for FileName in Files do
    begin
      try
        Content := GetFileContent(FileName);
        NewContent := RE.Replace(Content, FReplaceEdit.Text);
        if NewContent <> Content then
        begin
          Editor := FindOpenSourceEditor(FileName);
          if Editor <> nil then
            SetEditorText(Editor, NewContent)
          else
            TFile.WriteAllText(FileName, NewContent, TEncoding.UTF8);
          Inc(AffectedCount);
        end;
      except
        on E: Exception do
          MessageDlg(Format('Falha ao processar "%s": %s', [FileName, E.Message]), mtError, [mbOK], 0);
      end;
    end;
    FStatusLabel.Caption := Format('%d ficheiro(s) atualizado(s).', [AffectedCount]);
    SearchClick(nil);
  finally
    Files.Free;
  end;
end;

procedure TfrmGrepSearch.ResultsDblClick(Sender: TObject);
var
  Item: TListItem;
  FileName: string;
  LineNo, ColNo: Integer;
begin
  Item := FResultsList.Selected;
  if Item = nil then
    Exit;
  FileName := Item.SubItems[3];
  LineNo := StrToIntDef(Item.SubItems[0], 1);
  ColNo := StrToIntDef(Item.SubItems[1], 1);
  GotoEditorLine(FileName, LineNo, ColNo);
end;

procedure ShowGrepSearch;
begin
  if GrepForm = nil then
    GrepForm := TfrmGrepSearch.Create(Application);
  GrepForm.Show;
  GrepForm.BringToFront;
end;

initialization

finalization
  FreeAndNil(GrepForm);

end.
