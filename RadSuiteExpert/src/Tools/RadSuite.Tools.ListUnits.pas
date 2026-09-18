unit RadSuite.Tools.ListUnits;

interface

procedure ShowListUnits;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.IOUtils,
  ToolsAPI,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

type
  TfrmListUnits = class(TForm)
  private
    FFilterEdit: TEdit;
    FListView: TListView;
    FAllFiles: TArray<string>;
    procedure Populate(const Filter: string);
    procedure FilterChange(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmListUnits.Create(AOwner: TComponent);
var
  Top: Integer;
  Project: IOTAProject;
  F: string;
  List: TStringList;
begin
  inherited CreateNew(AOwner);
  Caption := 'List Units';
  ClientWidth := 480;
  ClientHeight := 520;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'List Units', 'Lista filtrável das units do projeto ativo');

  FFilterEdit := TEdit.Create(Self);
  FFilterEdit.Parent := Self;
  FFilterEdit.Top := Top;
  FFilterEdit.Align := alTop;
  FFilterEdit.OnChange := FilterChange;
  FFilterEdit.OnKeyDown := FilterKeyDown;
  FFilterEdit.TextHint := 'Filtrar por nome...';

  FListView := TListView.Create(Self);
  FListView.Parent := Self;
  FListView.Align := alClient;
  FListView.ViewStyle := vsReport;
  FListView.RowSelect := True;
  FListView.GridLines := True;
  FListView.OnDblClick := ListDblClick;
  with FListView.Columns.Add do begin Caption := 'Unit'; Width := 220; end;
  with FListView.Columns.Add do begin Caption := 'Caminho'; Width := 230; end;

  Project := GetActiveProject;
  List := TStringList.Create;
  try
    if Project <> nil then
      for F in GetProjectSourceFiles(Project) do
        if SameText(ExtractFileExt(F), '.pas') then
          List.Add(F);
    FAllFiles := List.ToStringArray;
  finally
    List.Free;
  end;

  Populate('');
  ActiveControl := FFilterEdit;
end;

procedure TfrmListUnits.Populate(const Filter: string);
var
  F: string;
  Item: TListItem;
begin
  FListView.Items.BeginUpdate;
  try
    FListView.Items.Clear;
    for F in FAllFiles do
      if (Filter = '') or (Pos(LowerCase(Filter), LowerCase(ExtractFileName(F))) > 0) then
      begin
        Item := FListView.Items.Add;
        Item.Caption := TPath.GetFileNameWithoutExtension(F);
        Item.SubItems.Add(F);
      end;
  finally
    FListView.Items.EndUpdate;
  end;
end;

procedure TfrmListUnits.FilterChange(Sender: TObject);
begin
  Populate(FFilterEdit.Text);
end;

procedure TfrmListUnits.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (FListView.Items.Count > 0) then
  begin
    GotoEditorLine(FListView.Items[0].SubItems[0], 1);
    Key := 0;
  end
  else if (Key = VK_DOWN) and (FListView.Items.Count > 0) then
  begin
    FListView.SetFocus;
    FListView.Items[0].Selected := True;
    Key := 0;
  end;
end;

procedure TfrmListUnits.ListDblClick(Sender: TObject);
begin
  if FListView.Selected <> nil then
    GotoEditorLine(FListView.Selected.SubItems[0], 1);
end;

procedure ShowListUnits;
var
  Form: TfrmListUnits;
begin
  Form := TfrmListUnits.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
