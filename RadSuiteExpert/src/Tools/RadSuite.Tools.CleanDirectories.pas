unit RadSuite.Tools.CleanDirectories;

interface

procedure ShowCleanDirectories;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs, Vcl.FileCtrl,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

const
  TempFileMasks: array[0..13] of string = (
    '*.dcu', '*.~*', '*.local', '*.identcache', '*.projdata', '*.tvsconfig',
    '*.dsk', '*.dsv', '*.stat', '*.map', '*.drc', '*.dres', '*.rsm', '*.tds');
  TempFolderNames: array[0..1] of string = ('__history', '__recovery');

type
  TfrmCleanDirectories = class(TForm)
  private
    FRootDir: string;
    FRootEdit: TEdit;
    FListView: TListView;
    FStatusLabel: TLabel;
    procedure BrowseClick(Sender: TObject);
    procedure ScanClick(Sender: TObject);
    procedure SelectSuggestedClick(Sender: TObject);
    procedure DeleteSelectedClick(Sender: TObject);
    procedure Scan;
    procedure AddEntry(const AKind, APath: string; ASize: Int64; ASuggested: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmCleanDirectories.Create(AOwner: TComponent);
var
  Top: Integer;
  ToolPanel, ButtonPanel: TPanel;
  BrowseButton, ScanButton, SelectSuggestedButton, DeleteButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Clean Directories';
  ClientWidth := 720;
  ClientHeight := 520;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Clean Directories',
    'Remove ficheiros temporários e pastas de histórico geradas pelo Delphi');

  ToolPanel := TPanel.Create(Self);
  ToolPanel.Parent := Self;
  ToolPanel.Top := Top;
  ToolPanel.Align := alTop;
  ToolPanel.Height := 40;
  ToolPanel.BevelOuter := bvNone;

  FRootEdit := TEdit.Create(Self);
  FRootEdit.Parent := ToolPanel;
  FRootEdit.Left := 12;
  FRootEdit.Top := 8;
  FRootEdit.Width := 420;
  FRootEdit.Text := GetActiveProjectDir;
  FRootDir := FRootEdit.Text;

  BrowseButton := TButton.Create(Self);
  BrowseButton.Parent := ToolPanel;
  BrowseButton.Caption := 'Procurar...';
  BrowseButton.Left := FRootEdit.Left + FRootEdit.Width + 8;
  BrowseButton.Top := 6;
  BrowseButton.Width := 90;
  BrowseButton.OnClick := BrowseClick;

  ScanButton := TButton.Create(Self);
  ScanButton.Parent := ToolPanel;
  ScanButton.Caption := 'Procurar ficheiros';
  ScanButton.Left := BrowseButton.Left + BrowseButton.Width + 8;
  ScanButton.Top := 6;
  ScanButton.Width := 120;
  ScanButton.OnClick := ScanClick;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  SelectSuggestedButton := TButton.Create(Self);
  SelectSuggestedButton.Parent := ButtonPanel;
  SelectSuggestedButton.Caption := 'Selecionar sugeridos';
  SelectSuggestedButton.Left := 12;
  SelectSuggestedButton.Top := 8;
  SelectSuggestedButton.Width := 150;
  SelectSuggestedButton.OnClick := SelectSuggestedClick;

  DeleteButton := TButton.Create(Self);
  DeleteButton.Parent := ButtonPanel;
  DeleteButton.Caption := 'Apagar selecionados';
  DeleteButton.Left := SelectSuggestedButton.Left + SelectSuggestedButton.Width + 8;
  DeleteButton.Top := 8;
  DeleteButton.Width := 150;
  DeleteButton.OnClick := DeleteSelectedClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := ButtonPanel;
  FStatusLabel.Left := DeleteButton.Left + DeleteButton.Width + 16;
  FStatusLabel.Top := 12;
  FStatusLabel.Caption := '';

  FListView := TListView.Create(Self);
  FListView.Parent := Self;
  FListView.Align := alClient;
  FListView.ViewStyle := vsReport;
  FListView.Checkboxes := True;
  FListView.RowSelect := True;
  FListView.GridLines := True;
  with FListView.Columns.Add do begin Caption := 'Tipo'; Width := 90; end;
  with FListView.Columns.Add do begin Caption := 'Caminho relativo'; Width := 420; end;
  with FListView.Columns.Add do begin Caption := 'Tamanho'; Width := 90; end;

  if FRootDir <> '' then
    Scan;
end;

procedure TfrmCleanDirectories.BrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := FRootEdit.Text;
  if SelectDirectory('Escolha a pasta do projeto', '', Dir) then
  begin
    FRootEdit.Text := Dir;
    FRootDir := Dir;
    Scan;
  end;
end;

procedure TfrmCleanDirectories.ScanClick(Sender: TObject);
begin
  FRootDir := FRootEdit.Text;
  Scan;
end;

procedure TfrmCleanDirectories.AddEntry(const AKind, APath: string; ASize: Int64; ASuggested: Boolean);
var
  Item: TListItem;
begin
  Item := FListView.Items.Add;
  Item.Caption := AKind;
  Item.Checked := ASuggested;
  Item.SubItems.Add(ExtractRelativePath(IncludeTrailingPathDelimiter(FRootDir), APath));
  Item.SubItems.Add(Format('%.0n KB', [ASize / 1024]));
end;

procedure TfrmCleanDirectories.Scan;
var
  Mask, Folder: string;
  Files, Folders: TArray<string>;
  F: string;
begin
  FListView.Items.Clear;
  if (FRootDir = '') or not TDirectory.Exists(FRootDir) then
  begin
    FStatusLabel.Caption := 'Pasta inválida.';
    Exit;
  end;

  for Mask in TempFileMasks do
  begin
    try
      Files := TDirectory.GetFiles(FRootDir, Mask, TSearchOption.soAllDirectories);
    except
      Files := [];
    end;
    for F in Files do
      AddEntry('Ficheiro', F, TFile.GetSize(F), True);
  end;

  for Folder in TempFolderNames do
  begin
    try
      Folders := TDirectory.GetDirectories(FRootDir, Folder, TSearchOption.soAllDirectories);
    except
      Folders := [];
    end;
    for F in Folders do
      AddEntry('Pasta', F, 0, False);
  end;

  FStatusLabel.Caption := Format('%d itens encontrados', [FListView.Items.Count]);
end;

procedure TfrmCleanDirectories.SelectSuggestedClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FListView.Items.Count - 1 do
    FListView.Items[I].Checked := FListView.Items[I].Caption = 'Ficheiro';
end;

procedure TfrmCleanDirectories.DeleteSelectedClick(Sender: TObject);
var
  I, Count: Integer;
  FullPath: string;
  ToDelete: TStringList;
begin
  ToDelete := TStringList.Create;
  try
    for I := 0 to FListView.Items.Count - 1 do
      if FListView.Items[I].Checked then
        ToDelete.Add(IntToStr(I));

    if ToDelete.Count = 0 then
    begin
      MessageDlg('Nenhum item selecionado.', mtInformation, [mbOK], 0);
      Exit;
    end;

    if MessageDlg(Format('Vai apagar %d item(ns). Esta ação não pode ser desfeita. Confirma?',
        [ToDelete.Count]), mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    Count := 0;
    for I := FListView.Items.Count - 1 downto 0 do
    begin
      if not FListView.Items[I].Checked then
        Continue;
      FullPath := IncludeTrailingPathDelimiter(FRootDir) + FListView.Items[I].SubItems[0];
      try
        if FListView.Items[I].Caption = 'Pasta' then
          TDirectory.Delete(FullPath, True)
        else
          TFile.Delete(FullPath);
        FListView.Items.Delete(I);
        Inc(Count);
      except
        on E: Exception do
          MessageDlg(Format('Falha ao apagar "%s": %s', [FullPath, E.Message]), mtError, [mbOK], 0);
      end;
    end;
    FStatusLabel.Caption := Format('%d item(ns) apagado(s).', [Count]);
  finally
    ToDelete.Free;
  end;
end;

procedure ShowCleanDirectories;
var
  Form: TfrmCleanDirectories;
begin
  Form := TfrmCleanDirectories.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
