unit RadSuite.Tools.AddMember;

interface

procedure ShowAddMember;

implementation

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

{
  Diálogo unificado "Adicionar Membro...": gera um esqueleto de código
  Pascal (campo, método, propriedade, procedure/function avulsa, class,
  interface, record ou variável local) e insere-o na posição do cursor.
  Não localiza automaticamente a secção correta da classe (private/public/
  etc.) nem separa declaração de implementação — é um gerador de esqueletos,
  não um modelo de código ao vivo.
}

type
  TMemberKind = (mkField, mkMethod, mkProperty, mkProcedure, mkClass, mkInterface, mkRecord, mkLocalVar);

const
  KindNames: array[TMemberKind] of string = (
    'Campo', 'Método', 'Propriedade', 'Procedure/Function avulsa',
    'Class', 'Interface', 'Record', 'Variável local');

  VisibilityNames: array[0..3] of string = ('private', 'protected', 'public', 'published');

function NewGuidString: string;
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) = 0 then
    Result := GUIDToString(Guid)
  else
    Result := '{00000000-0000-0000-0000-000000000000}';
end;

function IfThenEmpty(const AValue, ADefault: string): string;
begin
  if Trim(AValue) = '' then
    Result := ADefault
  else
    Result := AValue;
end;

function BuildSkeleton(Kind: TMemberKind; const Name_, TypeOrAncestor, Params, Visibility: string;
  IsFunction: Boolean): string;
begin
  case Kind of
    mkField:
      Result := Visibility + sLineBreak + '  ' + Name_ + ': ' + TypeOrAncestor + ';';

    mkMethod:
      begin
        Result := Visibility + sLineBreak + '  ';
        if IsFunction then
          Result := Result + 'function ' + Name_ + '(' + Params + '): ' + TypeOrAncestor + ';'
        else
          Result := Result + 'procedure ' + Name_ + '(' + Params + ');';
      end;

    mkProperty:
      Result := Visibility + sLineBreak + '  property ' + Name_ + ': ' + TypeOrAncestor +
        ' read F' + Name_ + ' write F' + Name_ + ';';

    mkProcedure:
      if IsFunction then
        Result := 'function ' + Name_ + '(' + Params + '): ' + TypeOrAncestor + ';'
      else
        Result := 'procedure ' + Name_ + '(' + Params + ');';

    mkClass:
      Result := 'T' + Name_ + ' = class(' + IfThenEmpty(TypeOrAncestor, 'TObject') + ')' + sLineBreak +
        '  public' + sLineBreak + sLineBreak + '  end;';

    mkInterface:
      Result := 'I' + Name_ + ' = interface(' + IfThenEmpty(TypeOrAncestor, 'IInterface') + ')' + sLineBreak +
        '    [''' + NewGuidString + ''']' + sLineBreak + sLineBreak + '  end;';

    mkRecord:
      Result := 'T' + Name_ + ' = record' + sLineBreak + sLineBreak + '  end;';

    mkLocalVar:
      Result := Name_ + ': ' + TypeOrAncestor + ';';
  end;
end;

type
  TfrmAddMember = class(TForm)
  private
    FKindCombo: TComboBox;
    FNameEdit, FTypeEdit, FParamsEdit: TEdit;
    FVisibilityCombo: TComboBox;
    FFunctionCheck: TCheckBox;
    FTypeLabel: TLabel;
    FOKButton, FCancelButton: TButton;
    procedure KindChange(Sender: TObject);
    procedure OKClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmAddMember.Create(AOwner: TComponent);
var
  Top: Integer;
  FieldsPanel, ButtonPanel: TPanel;
  KindLabel, NameLabel, ParamsLabel, VisibilityLabel: TLabel;
  K: TMemberKind;
begin
  inherited CreateNew(AOwner);
  Caption := 'Adicionar Membro';
  ClientWidth := 480;
  ClientHeight := 340;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'Adicionar Membro',
    'Gera um esqueleto de código e insere-o na posição do cursor');

  FieldsPanel := TPanel.Create(Self);
  FieldsPanel.Parent := Self;
  FieldsPanel.Top := Top;
  FieldsPanel.Align := alClient;
  FieldsPanel.BevelOuter := bvNone;

  KindLabel := TLabel.Create(Self);
  KindLabel.Parent := FieldsPanel;
  KindLabel.Left := 12;
  KindLabel.Top := 8;
  KindLabel.Caption := 'Tipo:';

  FKindCombo := TComboBox.Create(Self);
  FKindCombo.Parent := FieldsPanel;
  FKindCombo.Left := 12;
  FKindCombo.Top := 26;
  FKindCombo.Width := 220;
  FKindCombo.Style := csDropDownList;
  for K := Low(TMemberKind) to High(TMemberKind) do
    FKindCombo.Items.Add(KindNames[K]);
  FKindCombo.ItemIndex := 0;
  FKindCombo.OnChange := KindChange;

  FFunctionCheck := TCheckBox.Create(Self);
  FFunctionCheck.Parent := FieldsPanel;
  FFunctionCheck.Left := 250;
  FFunctionCheck.Top := 28;
  FFunctionCheck.Width := 200;
  FFunctionCheck.Caption := 'É função (tem retorno)';

  NameLabel := TLabel.Create(Self);
  NameLabel.Parent := FieldsPanel;
  NameLabel.Left := 12;
  NameLabel.Top := 60;
  NameLabel.Caption := 'Nome:';

  FNameEdit := TEdit.Create(Self);
  FNameEdit.Parent := FieldsPanel;
  FNameEdit.Left := 12;
  FNameEdit.Top := 78;
  FNameEdit.Width := 440;

  FTypeLabel := TLabel.Create(Self);
  FTypeLabel.Parent := FieldsPanel;
  FTypeLabel.Left := 12;
  FTypeLabel.Top := 108;
  FTypeLabel.Caption := 'Tipo:';

  FTypeEdit := TEdit.Create(Self);
  FTypeEdit.Parent := FieldsPanel;
  FTypeEdit.Left := 12;
  FTypeEdit.Top := 126;
  FTypeEdit.Width := 440;

  ParamsLabel := TLabel.Create(Self);
  ParamsLabel.Parent := FieldsPanel;
  ParamsLabel.Left := 12;
  ParamsLabel.Top := 156;
  ParamsLabel.Caption := 'Parâmetros (ex.: AValue: Integer; const AName: string):';

  FParamsEdit := TEdit.Create(Self);
  FParamsEdit.Parent := FieldsPanel;
  FParamsEdit.Left := 12;
  FParamsEdit.Top := 174;
  FParamsEdit.Width := 440;

  VisibilityLabel := TLabel.Create(Self);
  VisibilityLabel.Parent := FieldsPanel;
  VisibilityLabel.Left := 12;
  VisibilityLabel.Top := 204;
  VisibilityLabel.Caption := 'Visibilidade:';

  FVisibilityCombo := TComboBox.Create(Self);
  FVisibilityCombo.Parent := FieldsPanel;
  FVisibilityCombo.Left := 12;
  FVisibilityCombo.Top := 222;
  FVisibilityCombo.Width := 150;
  FVisibilityCombo.Style := csDropDownList;
  FVisibilityCombo.Items.AddStrings(VisibilityNames);
  FVisibilityCombo.ItemIndex := 0;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  FOKButton := TButton.Create(Self);
  FOKButton.Parent := ButtonPanel;
  FOKButton.Caption := 'Inserir';
  FOKButton.Default := True;
  FOKButton.Left := ButtonPanel.Width - 176;
  FOKButton.Top := 8;
  FOKButton.Anchors := [akTop, akRight];
  FOKButton.OnClick := OKClick;

  FCancelButton := TButton.Create(Self);
  FCancelButton.Parent := ButtonPanel;
  FCancelButton.Caption := 'Cancelar';
  FCancelButton.ModalResult := mrCancel;
  FCancelButton.Cancel := True;
  FCancelButton.Left := ButtonPanel.Width - 88;
  FCancelButton.Top := 8;
  FCancelButton.Anchors := [akTop, akRight];

  KindChange(nil);
end;

procedure TfrmAddMember.KindChange(Sender: TObject);
begin
  case TMemberKind(FKindCombo.ItemIndex) of
    mkField: FTypeLabel.Caption := 'Tipo do campo:';
    mkMethod: FTypeLabel.Caption := 'Tipo de retorno (se função):';
    mkProperty: FTypeLabel.Caption := 'Tipo da propriedade:';
    mkProcedure: FTypeLabel.Caption := 'Tipo de retorno (se função):';
    mkClass: FTypeLabel.Caption := 'Classe ancestral (vazio = TObject):';
    mkInterface: FTypeLabel.Caption := 'Interface ancestral (vazio = IInterface):';
    mkRecord: FTypeLabel.Caption := '(não aplicável)';
    mkLocalVar: FTypeLabel.Caption := 'Tipo da variável:';
  end;
end;

procedure TfrmAddMember.OKClick(Sender: TObject);
var
  Kind: TMemberKind;
  Skeleton: string;
begin
  if Trim(FNameEdit.Text) = '' then
  begin
    FNameEdit.SetFocus;
    Exit;
  end;
  Kind := TMemberKind(FKindCombo.ItemIndex);
  Skeleton := BuildSkeleton(Kind, Trim(FNameEdit.Text), Trim(FTypeEdit.Text), FParamsEdit.Text,
    VisibilityNames[FVisibilityCombo.ItemIndex], FFunctionCheck.Checked);
  InsertTextAtCursor(Skeleton);
  ModalResult := mrOk;
end;

procedure ShowAddMember;
var
  Form: TfrmAddMember;
begin
  Form := TfrmAddMember.Create(nil);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
