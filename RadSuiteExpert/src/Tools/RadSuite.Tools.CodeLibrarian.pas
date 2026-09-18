unit RadSuite.Tools.CodeLibrarian;

interface

procedure ShowCodeLibrarian;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils,
  System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

const
  SnippetStartMarker = '##RADSUITE-SNIPPET##';
  SnippetEndMarker = '##END##';
  SnippetBodyMarker = '---';
  DefaultCategory = 'Geral';

type
  TCodeSnippet = class
    Category: string;
    Name: string;
    Body: string;
  end;

function GetLibraryFilePath: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'RadSuite'), 'CodeLibrary.txt');
end;

procedure LoadSnippets(AList: TObjectList<TCodeSnippet>);
var
  Lines, Body: TStringList;
  I: Integer;
  Snippet: TCodeSnippet;
begin
  AList.Clear;
  if not TFile.Exists(GetLibraryFilePath) then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(GetLibraryFilePath, TEncoding.UTF8);
    I := 0;
    while I < Lines.Count do
    begin
      if SameText(Trim(Lines[I]), SnippetStartMarker) then
      begin
        Snippet := TCodeSnippet.Create;
        Snippet.Category := DefaultCategory;
        Inc(I);
        while (I < Lines.Count) and not SameText(Trim(Lines[I]), SnippetBodyMarker) do
        begin
          if StartsText('Category=', Lines[I]) then
            Snippet.Category := Copy(Lines[I], Length('Category=') + 1, MaxInt)
          else if StartsText('Name=', Lines[I]) then
            Snippet.Name := Copy(Lines[I], Length('Name=') + 1, MaxInt);
          Inc(I);
        end;
        Inc(I); // salta '---'
        Body := TStringList.Create;
        try
          while (I < Lines.Count) and not SameText(Trim(Lines[I]), SnippetEndMarker) do
          begin
            Body.Add(Lines[I]);
            Inc(I);
          end;
          Snippet.Body := Body.Text;
        finally
          Body.Free;
        end;
        AList.Add(Snippet);
      end;
      Inc(I);
    end;
  finally
    Lines.Free;
  end;
end;

procedure SaveSnippets(AList: TObjectList<TCodeSnippet>);
var
  Lines: TStringList;
  Snippet: TCodeSnippet;
begin
  TDirectory.CreateDirectory(ExtractFilePath(GetLibraryFilePath));
  Lines := TStringList.Create;
  try
    for Snippet in AList do
    begin
      Lines.Add(SnippetStartMarker);
      Lines.Add('Category=' + Snippet.Category);
      Lines.Add('Name=' + Snippet.Name);
      Lines.Add(SnippetBodyMarker);
      Lines.Add(Snippet.Body);
      Lines.Add(SnippetEndMarker);
    end;
    Lines.SaveToFile(GetLibraryFilePath, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

type
  TfrmSnippetEdit = class(TForm)
  private
    FCategoryEdit, FNameEdit: TEdit;
    FBodyMemo: TMemo;
  public
    constructor Create(AOwner: TComponent); override;
    property CategoryEdit: TEdit read FCategoryEdit;
    property NameEdit: TEdit read FNameEdit;
    property BodyMemo: TMemo read FBodyMemo;
  end;

constructor TfrmSnippetEdit.Create(AOwner: TComponent);
var
  Top: Integer;
  FieldsPanel, ButtonPanel: TPanel;
  CategoryLabel, NameLabel: TLabel;
  OKButton, CancelButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Snippet';
  ClientWidth := 560;
  ClientHeight := 420;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Snippet', 'Categoria, nome e código do snippet');

  FieldsPanel := TPanel.Create(Self);
  FieldsPanel.Parent := Self;
  FieldsPanel.Top := Top;
  FieldsPanel.Align := alTop;
  FieldsPanel.Height := 76;
  FieldsPanel.BevelOuter := bvNone;

  CategoryLabel := TLabel.Create(Self);
  CategoryLabel.Parent := FieldsPanel;
  CategoryLabel.Left := 12;
  CategoryLabel.Top := 4;
  CategoryLabel.Caption := 'Categoria:';

  FCategoryEdit := TEdit.Create(Self);
  FCategoryEdit.Parent := FieldsPanel;
  FCategoryEdit.Left := 12;
  FCategoryEdit.Top := 22;
  FCategoryEdit.Width := 520;

  NameLabel := TLabel.Create(Self);
  NameLabel.Parent := FieldsPanel;
  NameLabel.Left := 12;
  NameLabel.Top := 48;
  NameLabel.Caption := 'Nome:';

  FNameEdit := TEdit.Create(Self);
  FNameEdit.Parent := FieldsPanel;
  FNameEdit.Left := 12;
  FNameEdit.Top := 66;
  FNameEdit.Width := 520;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  OKButton := TButton.Create(Self);
  OKButton.Parent := ButtonPanel;
  OKButton.Caption := 'OK';
  OKButton.ModalResult := mrOk;
  OKButton.Default := True;
  OKButton.Left := ButtonPanel.Width - 176;
  OKButton.Top := 8;
  OKButton.Anchors := [akTop, akRight];

  CancelButton := TButton.Create(Self);
  CancelButton.Parent := ButtonPanel;
  CancelButton.Caption := 'Cancelar';
  CancelButton.ModalResult := mrCancel;
  CancelButton.Cancel := True;
  CancelButton.Left := ButtonPanel.Width - 88;
  CancelButton.Top := 8;
  CancelButton.Anchors := [akTop, akRight];

  FBodyMemo := TMemo.Create(Self);
  FBodyMemo.Parent := Self;
  FBodyMemo.Align := alClient;
  FBodyMemo.ScrollBars := ssBoth;
  FBodyMemo.WordWrap := False;
  FBodyMemo.Font.Name := 'Consolas';
  FBodyMemo.Font.Size := 9;
end;

type
  TfrmCodeLibrarian = class(TForm)
  private
    FSnippets: TObjectList<TCodeSnippet>;
    FTree: TTreeView;
    FPreviewMemo: TMemo;
    procedure PopulateTree;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    function SelectedSnippet: TCodeSnippet;
    procedure NewClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure InsertClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TfrmCodeLibrarian.Create(AOwner: TComponent);
var
  Top: Integer;
  Splitter: TSplitter;
  ButtonPanel: TPanel;
  NewButton, EditButton, DeleteButton, InsertButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Code Librarian';
  ClientWidth := 760;
  ClientHeight := 540;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  FSnippets := TObjectList<TCodeSnippet>.Create(True);
  LoadSnippets(FSnippets);

  Top := AddRadSuiteHeader(Self, 'Code Librarian', 'Snippets de código reutilizáveis');

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  NewButton := TButton.Create(Self);
  NewButton.Parent := ButtonPanel;
  NewButton.Caption := 'Novo';
  NewButton.Left := 12;
  NewButton.Top := 8;
  NewButton.Width := 90;
  NewButton.OnClick := NewClick;

  EditButton := TButton.Create(Self);
  EditButton.Parent := ButtonPanel;
  EditButton.Caption := 'Editar';
  EditButton.Left := 108;
  EditButton.Top := 8;
  EditButton.Width := 90;
  EditButton.OnClick := EditClick;

  DeleteButton := TButton.Create(Self);
  DeleteButton.Parent := ButtonPanel;
  DeleteButton.Caption := 'Apagar';
  DeleteButton.Left := 204;
  DeleteButton.Top := 8;
  DeleteButton.Width := 90;
  DeleteButton.OnClick := DeleteClick;

  InsertButton := TButton.Create(Self);
  InsertButton.Parent := ButtonPanel;
  InsertButton.Caption := 'Inserir no editor';
  InsertButton.Left := 320;
  InsertButton.Top := 8;
  InsertButton.Width := 130;
  InsertButton.OnClick := InsertClick;

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Top := Top;
  FTree.Left := 0;
  FTree.Width := 260;
  FTree.Align := alLeft;
  FTree.ReadOnly := True;
  FTree.OnChange := TreeChange;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Left := 260;
  Splitter.Top := Top;
  Splitter.Width := 4;

  FPreviewMemo := TMemo.Create(Self);
  FPreviewMemo.Parent := Self;
  FPreviewMemo.Top := Top;
  FPreviewMemo.Align := alClient;
  FPreviewMemo.ReadOnly := True;
  FPreviewMemo.ScrollBars := ssBoth;
  FPreviewMemo.WordWrap := False;
  FPreviewMemo.Font.Name := 'Consolas';
  FPreviewMemo.Font.Size := 9;

  PopulateTree;
end;

destructor TfrmCodeLibrarian.Destroy;
begin
  FSnippets.Free;
  inherited;
end;

procedure TfrmCodeLibrarian.PopulateTree;
var
  Snippet: TCodeSnippet;
  CategoryNode, SnippetNode: TTreeNode;
  I: Integer;

  function FindOrAddCategory(const ACategory: string): TTreeNode;
  var
    N: TTreeNode;
  begin
    for N in FTree.Items do
      if (N.Level = 0) and SameText(N.Text, ACategory) then
        Exit(N);
    Result := FTree.Items.Add(nil, ACategory);
  end;

begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    for I := 0 to FSnippets.Count - 1 do
    begin
      Snippet := FSnippets[I];
      CategoryNode := FindOrAddCategory(Snippet.Category);
      SnippetNode := FTree.Items.AddChild(CategoryNode, Snippet.Name);
      SnippetNode.Data := Pointer(NativeInt(I));
    end;
    FTree.FullExpand;
  finally
    FTree.Items.EndUpdate;
  end;
end;

function TfrmCodeLibrarian.SelectedSnippet: TCodeSnippet;
var
  Index: NativeInt;
begin
  Result := nil;
  if (FTree.Selected <> nil) and (FTree.Selected.Data <> nil) then
  begin
    Index := NativeInt(FTree.Selected.Data);
    if (Index >= 0) and (Index < FSnippets.Count) then
      Result := FSnippets[Index];
  end;
end;

procedure TfrmCodeLibrarian.TreeChange(Sender: TObject; Node: TTreeNode);
var
  Snippet: TCodeSnippet;
begin
  Snippet := SelectedSnippet;
  if Snippet <> nil then
    FPreviewMemo.Text := Snippet.Body
  else
    FPreviewMemo.Text := '';
end;

procedure TfrmCodeLibrarian.NewClick(Sender: TObject);
var
  Dlg: TfrmSnippetEdit;
  Snippet: TCodeSnippet;
begin
  Dlg := TfrmSnippetEdit.Create(nil);
  try
    Dlg.CategoryEdit.Text := DefaultCategory;
    Dlg.BodyMemo.Text := GetSelectedText(GetActiveSourceEditor);
    if Dlg.ShowModal = mrOk then
    begin
      if Trim(Dlg.NameEdit.Text) = '' then
      begin
        MessageDlg('Indique um nome para o snippet.', mtWarning, [mbOK], 0);
        Exit;
      end;
      Snippet := TCodeSnippet.Create;
      Snippet.Category := IfThen(Trim(Dlg.CategoryEdit.Text) = '', DefaultCategory, Dlg.CategoryEdit.Text);
      Snippet.Name := Dlg.NameEdit.Text;
      Snippet.Body := Dlg.BodyMemo.Text;
      FSnippets.Add(Snippet);
      SaveSnippets(FSnippets);
      PopulateTree;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmCodeLibrarian.EditClick(Sender: TObject);
var
  Dlg: TfrmSnippetEdit;
  Snippet: TCodeSnippet;
begin
  Snippet := SelectedSnippet;
  if Snippet = nil then
  begin
    MessageDlg('Selecione um snippet.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Dlg := TfrmSnippetEdit.Create(nil);
  try
    Dlg.CategoryEdit.Text := Snippet.Category;
    Dlg.NameEdit.Text := Snippet.Name;
    Dlg.BodyMemo.Text := Snippet.Body;
    if Dlg.ShowModal = mrOk then
    begin
      Snippet.Category := IfThen(Trim(Dlg.CategoryEdit.Text) = '', DefaultCategory, Dlg.CategoryEdit.Text);
      Snippet.Name := Dlg.NameEdit.Text;
      Snippet.Body := Dlg.BodyMemo.Text;
      SaveSnippets(FSnippets);
      PopulateTree;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmCodeLibrarian.DeleteClick(Sender: TObject);
var
  Snippet: TCodeSnippet;
begin
  Snippet := SelectedSnippet;
  if Snippet = nil then
  begin
    MessageDlg('Selecione um snippet.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if MessageDlg(Format('Apagar o snippet "%s"?', [Snippet.Name]), mtWarning, [mbYes, mbNo], 0) = mrYes then
  begin
    FSnippets.Remove(Snippet);
    SaveSnippets(FSnippets);
    PopulateTree;
    FPreviewMemo.Text := '';
  end;
end;

procedure TfrmCodeLibrarian.InsertClick(Sender: TObject);
var
  Snippet: TCodeSnippet;
begin
  Snippet := SelectedSnippet;
  if Snippet = nil then
  begin
    MessageDlg('Selecione um snippet.', mtInformation, [mbOK], 0);
    Exit;
  end;
  InsertTextAtCursor(Snippet.Body);
end;

procedure ShowCodeLibrarian;
var
  Form: TfrmCodeLibrarian;
begin
  Form := TfrmCodeLibrarian.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
