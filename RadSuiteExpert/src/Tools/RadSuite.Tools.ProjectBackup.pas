unit RadSuite.Tools.ProjectBackup;

interface

procedure ShowProjectBackup;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.FileCtrl,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

type
  TfrmProjectBackup = class(TForm)
  private
    FSourceEdit, FDestEdit: TEdit;
    FStatusLabel: TLabel;
    procedure BrowseSourceClick(Sender: TObject);
    procedure BrowseDestClick(Sender: TObject);
    procedure BackupClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmProjectBackup.Create(AOwner: TComponent);
var
  Top: Integer;
  FieldsPanel, ButtonPanel: TPanel;
  SourceLabel, DestLabel: TLabel;
  BrowseSourceButton, BrowseDestButton, BackupButton: TButton;
  ProjectDir: string;
begin
  inherited CreateNew(AOwner);
  Caption := 'Project Backup';
  ClientWidth := 560;
  ClientHeight := 260;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Project Backup', 'Cria um .zip do código-fonte do projeto ativo');

  FieldsPanel := TPanel.Create(Self);
  FieldsPanel.Parent := Self;
  FieldsPanel.Top := Top;
  FieldsPanel.Align := alClient;
  FieldsPanel.BevelOuter := bvNone;

  SourceLabel := TLabel.Create(Self);
  SourceLabel.Parent := FieldsPanel;
  SourceLabel.Left := 12;
  SourceLabel.Top := 8;
  SourceLabel.Caption := 'Pasta do projeto (será compactada, incluindo subpastas):';

  FSourceEdit := TEdit.Create(Self);
  FSourceEdit.Parent := FieldsPanel;
  FSourceEdit.Left := 12;
  FSourceEdit.Top := 26;
  FSourceEdit.Width := 420;

  BrowseSourceButton := TButton.Create(Self);
  BrowseSourceButton.Parent := FieldsPanel;
  BrowseSourceButton.Left := 440;
  BrowseSourceButton.Top := 24;
  BrowseSourceButton.Width := 30;
  BrowseSourceButton.Caption := '...';
  BrowseSourceButton.OnClick := BrowseSourceClick;

  DestLabel := TLabel.Create(Self);
  DestLabel.Parent := FieldsPanel;
  DestLabel.Left := 12;
  DestLabel.Top := 60;
  DestLabel.Caption := 'Pasta de destino dos backups:';

  FDestEdit := TEdit.Create(Self);
  FDestEdit.Parent := FieldsPanel;
  FDestEdit.Left := 12;
  FDestEdit.Top := 78;
  FDestEdit.Width := 420;

  BrowseDestButton := TButton.Create(Self);
  BrowseDestButton.Parent := FieldsPanel;
  BrowseDestButton.Left := 440;
  BrowseDestButton.Top := 76;
  BrowseDestButton.Width := 30;
  BrowseDestButton.Caption := '...';
  BrowseDestButton.OnClick := BrowseDestClick;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  BackupButton := TButton.Create(Self);
  BackupButton.Parent := ButtonPanel;
  BackupButton.Left := 12;
  BackupButton.Top := 8;
  BackupButton.Width := 150;
  BackupButton.Caption := 'Fazer backup agora';
  BackupButton.OnClick := BackupClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.WordWrap := True;
  FStatusLabel.Caption := '';

  ProjectDir := GetActiveProjectDir;
  FSourceEdit.Text := ProjectDir;
  if ProjectDir <> '' then
    FDestEdit.Text := IncludeTrailingPathDelimiter(
      TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(ProjectDir))) + 'Backups';
end;

procedure TfrmProjectBackup.BrowseSourceClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := FSourceEdit.Text;
  if SelectDirectory('Escolha a pasta do projeto', '', Dir) then
    FSourceEdit.Text := Dir;
end;

procedure TfrmProjectBackup.BrowseDestClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := FDestEdit.Text;
  if SelectDirectory('Escolha a pasta de destino', '', Dir) then
    FDestEdit.Text := Dir;
end;

procedure TfrmProjectBackup.BackupClick(Sender: TObject);
var
  ZipPath, ProjectName: string;
begin
  if not TDirectory.Exists(FSourceEdit.Text) then
  begin
    MessageDlg('Pasta de origem inválida.', mtError, [mbOK], 0);
    Exit;
  end;
  TDirectory.CreateDirectory(FDestEdit.Text);
  ProjectName := ExtractFileName(ExcludeTrailingPathDelimiter(FSourceEdit.Text));
  if ProjectName = '' then
    ProjectName := 'Projeto';
  ZipPath := IncludeTrailingPathDelimiter(FDestEdit.Text) +
    Format('%s_%s.zip', [ProjectName, FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now)]);

  try
    TZipFile.ZipDirectoryContents(ZipPath, FSourceEdit.Text, zcDeflate);
    FStatusLabel.Caption := 'Backup criado: ' + ZipPath;
  except
    on E: Exception do
      MessageDlg('Falha ao criar o backup: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure ShowProjectBackup;
var
  Form: TfrmProjectBackup;
begin
  Form := TfrmProjectBackup.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
