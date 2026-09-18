unit RadSuite.Tools.AsciiChart;

interface

procedure ShowAsciiChart;

implementation

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.ComCtrls, Vcl.Controls,
  Vcl.StdCtrls, Vcl.Clipbrd, Vcl.ExtCtrls,
  RadSuite.UI.Theme;

type
  TfrmAsciiChart = class(TForm)
  private
    FListView: TListView;
    FCopyButton: TButton;
    procedure PopulateChart;
    procedure CopyButtonClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

{ TfrmAsciiChart }

constructor TfrmAsciiChart.Create(AOwner: TComponent);
var
  Top: Integer;
  ButtonPanel: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := 'ASCII Chart';
  ClientWidth := 420;
  ClientHeight := 560;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'ASCII Chart', 'Tabela de caracteres ASCII (0-255)');

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  FCopyButton := TButton.Create(Self);
  FCopyButton.Parent := ButtonPanel;
  FCopyButton.Caption := 'Copiar caractere selecionado';
  FCopyButton.Left := 12;
  FCopyButton.Top := 8;
  FCopyButton.Width := 220;
  FCopyButton.OnClick := CopyButtonClick;

  FListView := TListView.Create(Self);
  FListView.Parent := Self;
  FListView.Top := Top;
  FListView.Align := alClient;
  FListView.ViewStyle := vsReport;
  FListView.ReadOnly := True;
  FListView.RowSelect := True;
  FListView.GridLines := True;
  FListView.OnDblClick := CopyButtonClick;
  with FListView.Columns.Add do begin Caption := 'Dec'; Width := 60; end;
  with FListView.Columns.Add do begin Caption := 'Hex'; Width := 60; end;
  with FListView.Columns.Add do begin Caption := 'Caractere'; Width := 80; end;
  with FListView.Columns.Add do begin Caption := 'Nome/Descrição'; Width := 180; end;

  PopulateChart;
end;

procedure TfrmAsciiChart.PopulateChart;
const
  ControlNames: array[0..32] of string = (
    'NUL', 'SOH', 'STX', 'ETX', 'EOT', 'ENQ', 'ACK', 'BEL', 'BS', 'TAB',
    'LF', 'VT', 'FF', 'CR', 'SO', 'SI', 'DLE', 'DC1', 'DC2', 'DC3', 'DC4',
    'NAK', 'SYN', 'ETB', 'CAN', 'EM', 'SUB', 'ESC', 'FS', 'GS', 'RS', 'US',
    'SPACE');
var
  I: Integer;
  Item: TListItem;
begin
  FListView.Items.BeginUpdate;
  try
    FListView.Items.Clear;
    for I := 0 to 255 do
    begin
      Item := FListView.Items.Add;
      Item.Caption := IntToStr(I);
      Item.SubItems.Add('$' + IntToHex(I, 2));
      if (I <= 32) or (I = 127) then
        Item.SubItems.Add('')
      else
        Item.SubItems.Add(Char(I));
      if I <= 32 then
        Item.SubItems.Add(ControlNames[I])
      else if I = 127 then
        Item.SubItems.Add('DEL')
      else
        Item.SubItems.Add('');
    end;
  finally
    FListView.Items.EndUpdate;
  end;
end;

procedure TfrmAsciiChart.CopyButtonClick(Sender: TObject);
begin
  if Assigned(FListView.Selected) then
    Clipboard.AsText := FListView.Selected.SubItems[1];
end;

procedure ShowAsciiChart;
var
  Form: TfrmAsciiChart;
begin
  Form := TfrmAsciiChart.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
