unit RadSuite.Tools.ProjectDirBuilder;

interface

procedure ShowProjectDirBuilder;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.FileCtrl,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

const
  DefaultFolders =
    'src' + sLineBreak +
    'src\Forms' + sLineBreak +
    'src\Model' + sLineBreak +
    'src\Services' + sLineBreak +
    'docs' + sLineBreak +
    'tests' + sLineBreak +
    'lib';

type
  TfrmProjectDirBuilder = class(TForm)
  private
    FBaseDirEdit: TEdit;
    FFoldersMemo: TMemo;
    FStatusLabel: TLabel;
    procedure BrowseClick(Sender: TObject);
    procedure CreateClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmProjectDirBuilder.Create(AOwner: TComponent);
var
  Top: Integer;
  TopPanel, ButtonPanel: TPanel;
  BaseLabel: TLabel;
  BrowseButton, CreateButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Project Dir Builder';
  ClientWidth := 480;
  ClientHeight := 480;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Project Dir Builder',
    'Cria a estrutura de pastas indicada abaixo (uma por linha, caminhos relativos)');

  TopPanel := TPanel.Create(Self);
  TopPanel.Parent := Self;
  TopPanel.Top := Top;
  TopPanel.Align := alTop;
  TopPanel.Height := 58;
  TopPanel.BevelOuter := bvNone;

  BaseLabel := TLabel.Create(Self);
  BaseLabel.Parent := TopPanel;
  BaseLabel.Left := 12;
  BaseLabel.Top := 4;
  BaseLabel.Caption := 'Pasta base:';

  FBaseDirEdit := TEdit.Create(Self);
  FBaseDirEdit.Parent := TopPanel;
  FBaseDirEdit.Left := 12;
  FBaseDirEdit.Top := 22;
  FBaseDirEdit.Width := 380;
  FBaseDirEdit.Text := GetActiveProjectDir;

  BrowseButton := TButton.Create(Self);
  BrowseButton.Parent := TopPanel;
  BrowseButton.Left := 400;
  BrowseButton.Top := 20;
  BrowseButton.Width := 30;
  BrowseButton.Caption := '...';
  BrowseButton.OnClick := BrowseClick;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 60;
  ButtonPanel.BevelOuter := bvNone;

  CreateButton := TButton.Create(Self);
  CreateButton.Parent := ButtonPanel;
  CreateButton.Left := 12;
  CreateButton.Top := 8;
  CreateButton.Width := 150;
  CreateButton.Caption := 'Criar pastas';
  CreateButton.OnClick := CreateClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := ButtonPanel;
  FStatusLabel.Left := 12;
  FStatusLabel.Top := 36;
  FStatusLabel.Width := 440;
  FStatusLabel.WordWrap := True;
  FStatusLabel.Caption := '';

  FFoldersMemo := TMemo.Create(Self);
  FFoldersMemo.Parent := Self;
  FFoldersMemo.Align := alClient;
  FFoldersMemo.ScrollBars := ssVertical;
  FFoldersMemo.Font.Name := 'Consolas';
  FFoldersMemo.Font.Size := 9;
  FFoldersMemo.Lines.Text := DefaultFolders;
end;

procedure TfrmProjectDirBuilder.BrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := FBaseDirEdit.Text;
  if SelectDirectory('Escolha a pasta base', '', Dir) then
    FBaseDirEdit.Text := Dir;
end;

procedure TfrmProjectDirBuilder.CreateClick(Sender: TObject);
var
  I, Created: Integer;
  Folder, FullPath: string;
begin
  if not TDirectory.Exists(FBaseDirEdit.Text) then
  begin
    MessageDlg('Pasta base inválida.', mtError, [mbOK], 0);
    Exit;
  end;
  Created := 0;
  for I := 0 to FFoldersMemo.Lines.Count - 1 do
  begin
    Folder := Trim(FFoldersMemo.Lines[I]);
    if Folder = '' then
      Continue;
    FullPath := IncludeTrailingPathDelimiter(FBaseDirEdit.Text) + Folder;
    try
      if not TDirectory.Exists(FullPath) then
      begin
        TDirectory.CreateDirectory(FullPath);
        Inc(Created);
      end;
    except
      on E: Exception do
        MessageDlg(Format('Falha ao criar "%s": %s', [FullPath, E.Message]), mtError, [mbOK], 0);
    end;
  end;
  FStatusLabel.Caption := Format('%d pasta(s) criada(s).', [Created]);
end;

procedure ShowProjectDirBuilder;
var
  Form: TfrmProjectDirBuilder;
begin
  Form := TfrmProjectDirBuilder.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
