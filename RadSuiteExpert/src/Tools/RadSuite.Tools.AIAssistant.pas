unit RadSuite.Tools.AIAssistant;

interface

procedure ShowAIAssistant;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  System.StrUtils, System.JSON, System.Net.HttpClient, System.Net.URLClient,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  RadSuite.UI.Theme, RadSuite.IDE.Utils;

const
  DefaultModel = 'claude-sonnet-5';
  AnthropicEndpoint = 'https://api.anthropic.com/v1/messages';
  AnthropicVersion = '2023-06-01';

function GetConfigFilePath: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'RadSuite'), 'ai-config.ini');
end;

procedure LoadConfig(out APIKey, Model: string);
var
  Ini: TIniFile;
begin
  APIKey := '';
  Model := DefaultModel;
  if TFile.Exists(GetConfigFilePath) then
  begin
    Ini := TIniFile.Create(GetConfigFilePath);
    try
      APIKey := Ini.ReadString('AI', 'APIKey', '');
      Model := Ini.ReadString('AI', 'Model', Model);
    finally
      Ini.Free;
    end;
  end;
end;

procedure SaveConfig(const APIKey, Model: string);
var
  Ini: TIniFile;
begin
  TDirectory.CreateDirectory(ExtractFilePath(GetConfigFilePath));
  Ini := TIniFile.Create(GetConfigFilePath);
  try
    Ini.WriteString('AI', 'APIKey', APIKey);
    Ini.WriteString('AI', 'Model', Model);
  finally
    Ini.Free;
  end;
end;

function BuildRequestBody(const Model, UserContent: string): string;
var
  Root, MessageObj: TJSONObject;
  Messages: TJSONArray;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('model', Model);
    Root.AddPair('max_tokens', TJSONNumber.Create(4096));
    Messages := TJSONArray.Create;
    MessageObj := TJSONObject.Create;
    MessageObj.AddPair('role', 'user');
    MessageObj.AddPair('content', UserContent);
    Messages.AddElement(MessageObj);
    Root.AddPair('messages', Messages);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function ExtractResponseText(const JSONText: string): string;
var
  Root: TJSONObject;
  ContentArray: TJSONArray;
  ErrorObj: TJSONObject;
  Msg: string;
  Parsed: TJSONValue;
begin
  Result := '';
  Parsed := TJSONObject.ParseJSONValue(JSONText);
  if not (Parsed is TJSONObject) then
    raise Exception.Create('Resposta inválida (JSON não reconhecido).');
  Root := TJSONObject(Parsed);
  try
    if Root.TryGetValue<TJSONObject>('error', ErrorObj) then
    begin
      if not ErrorObj.TryGetValue<string>('message', Msg) then
        Msg := 'erro desconhecido';
      raise Exception.Create('Erro da API: ' + Msg);
    end;
    if Root.TryGetValue<TJSONArray>('content', ContentArray) and (ContentArray.Count > 0) then
      (ContentArray.Items[0] as TJSONObject).TryGetValue<string>('text', Result);
  finally
    Root.Free;
  end;
end;

procedure SendRequest(const APIKey, Model, UserContent: string; const OnDone: TProc<string, Boolean>);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Client: THTTPClient;
      RequestBody: TStringStream;
      Response: IHTTPResponse;
      ResponseText, ErrorMsg: string;
      Success: Boolean;
    begin
      Success := False;
      ResponseText := '';
      ErrorMsg := '';
      Client := THTTPClient.Create;
      RequestBody := TStringStream.Create(BuildRequestBody(Model, UserContent), TEncoding.UTF8);
      try
        Client.ContentType := 'application/json';
        try
          Response := Client.Post(AnthropicEndpoint, RequestBody, nil,
            [TNetHeader.Create('x-api-key', APIKey), TNetHeader.Create('anthropic-version', AnthropicVersion)]);
          if Response.StatusCode = 200 then
          begin
            try
              ResponseText := ExtractResponseText(Response.ContentAsString(TEncoding.UTF8));
              Success := True;
            except
              on E: Exception do
                ErrorMsg := E.Message;
            end;
          end
          else
            ErrorMsg := Format('HTTP %d: %s', [Response.StatusCode, Response.ContentAsString(TEncoding.UTF8)]);
        except
          on E: Exception do
            ErrorMsg := 'Falha de rede: ' + E.Message;
        end;
      finally
        RequestBody.Free;
        Client.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Success then
            OnDone(ResponseText, True)
          else
            OnDone(ErrorMsg, False);
        end);
    end).Start;
end;

type
  TfrmAIConfig = class(TForm)
  private
    FAPIKeyEdit, FModelEdit: TEdit;
  public
    constructor Create(AOwner: TComponent); override;
    property APIKeyEdit: TEdit read FAPIKeyEdit;
    property ModelEdit: TEdit read FModelEdit;
  end;

constructor TfrmAIConfig.Create(AOwner: TComponent);
var
  Top: Integer;
  FieldsPanel, ButtonPanel: TPanel;
  KeyLabel, ModelLabel, HintLabel: TLabel;
  OKButton, CancelButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'Configurar AI Assistant';
  ClientWidth := 460;
  ClientHeight := 260;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'AI Assistant', 'Configuração da API Claude (Anthropic)');

  FieldsPanel := TPanel.Create(Self);
  FieldsPanel.Parent := Self;
  FieldsPanel.Top := Top;
  FieldsPanel.Align := alClient;
  FieldsPanel.BevelOuter := bvNone;

  KeyLabel := TLabel.Create(Self);
  KeyLabel.Parent := FieldsPanel;
  KeyLabel.Left := 12;
  KeyLabel.Top := 8;
  KeyLabel.Caption := 'API Key (Anthropic):';

  FAPIKeyEdit := TEdit.Create(Self);
  FAPIKeyEdit.Parent := FieldsPanel;
  FAPIKeyEdit.Left := 12;
  FAPIKeyEdit.Top := 26;
  FAPIKeyEdit.Width := 420;
  FAPIKeyEdit.PasswordChar := '*';

  ModelLabel := TLabel.Create(Self);
  ModelLabel.Parent := FieldsPanel;
  ModelLabel.Left := 12;
  ModelLabel.Top := 60;
  ModelLabel.Caption := 'Modelo:';

  FModelEdit := TEdit.Create(Self);
  FModelEdit.Parent := FieldsPanel;
  FModelEdit.Left := 12;
  FModelEdit.Top := 78;
  FModelEdit.Width := 420;
  FModelEdit.Text := DefaultModel;

  HintLabel := TLabel.Create(Self);
  HintLabel.Parent := FieldsPanel;
  HintLabel.Left := 12;
  HintLabel.Top := 110;
  HintLabel.Width := 420;
  HintLabel.WordWrap := True;
  HintLabel.Font.Color := RadSuiteMutedTextColor;
  HintLabel.Caption := 'A API key fica guardada apenas neste computador (' + GetConfigFilePath +
    '), nunca é enviada para o repositório. Ao usar o AI Assistant, o texto do prompt ' +
    'e o código selecionado (se incluído) são enviados para a API da Anthropic.';

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
end;

type
  TfrmAIAssistant = class(TForm)
  private
    FAPIKey, FModel: string;
    FPromptMemo, FResponseMemo: TMemo;
    FIncludeSelectionCheck: TCheckBox;
    FSendButton, FInsertButton, FReplaceButton, FConfigButton: TButton;
    FStatusLabel: TLabel;
    procedure ConfigClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure InsertClick(Sender: TObject);
    procedure ReplaceClick(Sender: TObject);
    procedure HandleResponse(const AText: string; ASuccess: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  AIForm: TfrmAIAssistant;

constructor TfrmAIAssistant.Create(AOwner: TComponent);
var
  Top: Integer;
  TopPanel, ButtonPanel: TPanel;
  VSplitter: TSplitter;
begin
  inherited CreateNew(AOwner);
  Caption := 'AI Assistant';
  ClientWidth := 640;
  ClientHeight := 560;
  BorderStyle := bsSizeable;
  Position := poScreenCenter;
  ApplyRadSuiteStyle(Self);

  LoadConfig(FAPIKey, FModel);

  Top := AddRadSuiteHeader(Self, 'AI Assistant',
    'Assistente de código com Claude (Anthropic) - requer API key própria');

  TopPanel := TPanel.Create(Self);
  TopPanel.Parent := Self;
  TopPanel.Top := Top;
  TopPanel.Align := alTop;
  TopPanel.Height := 34;
  TopPanel.BevelOuter := bvNone;

  FIncludeSelectionCheck := TCheckBox.Create(Self);
  FIncludeSelectionCheck.Parent := TopPanel;
  FIncludeSelectionCheck.Left := 12;
  FIncludeSelectionCheck.Top := 8;
  FIncludeSelectionCheck.Width := 260;
  FIncludeSelectionCheck.Caption := 'Incluir código selecionado como contexto';
  FIncludeSelectionCheck.Checked := True;

  FConfigButton := TButton.Create(Self);
  FConfigButton.Parent := TopPanel;
  FConfigButton.Left := 540;
  FConfigButton.Top := 4;
  FConfigButton.Width := 90;
  FConfigButton.Caption := 'Configurar...';
  FConfigButton.OnClick := ConfigClick;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alBottom;
  ButtonPanel.Height := 44;
  ButtonPanel.BevelOuter := bvNone;

  FSendButton := TButton.Create(Self);
  FSendButton.Parent := ButtonPanel;
  FSendButton.Left := 12;
  FSendButton.Top := 8;
  FSendButton.Width := 100;
  FSendButton.Caption := 'Enviar';
  FSendButton.OnClick := SendClick;

  FInsertButton := TButton.Create(Self);
  FInsertButton.Parent := ButtonPanel;
  FInsertButton.Left := 120;
  FInsertButton.Top := 8;
  FInsertButton.Width := 140;
  FInsertButton.Caption := 'Inserir no editor';
  FInsertButton.OnClick := InsertClick;

  FReplaceButton := TButton.Create(Self);
  FReplaceButton.Parent := ButtonPanel;
  FReplaceButton.Left := 268;
  FReplaceButton.Top := 8;
  FReplaceButton.Width := 140;
  FReplaceButton.Caption := 'Substituir seleção';
  FReplaceButton.OnClick := ReplaceClick;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Alignment := taCenter;
  FStatusLabel.Caption := IfThen(FAPIKey = '', 'Configure a API key antes de usar.', 'Pronto.');

  FPromptMemo := TMemo.Create(Self);
  FPromptMemo.Parent := Self;
  FPromptMemo.Top := Top + 34;
  FPromptMemo.Align := alTop;
  FPromptMemo.Height := 160;
  FPromptMemo.ScrollBars := ssVertical;
  FPromptMemo.WordWrap := True;

  VSplitter := TSplitter.Create(Self);
  VSplitter.Parent := Self;
  VSplitter.Top := Top + 34 + 160;
  VSplitter.Align := alTop;
  VSplitter.Height := 4;

  FResponseMemo := TMemo.Create(Self);
  FResponseMemo.Parent := Self;
  FResponseMemo.Align := alClient;
  FResponseMemo.ReadOnly := True;
  FResponseMemo.ScrollBars := ssBoth;
  FResponseMemo.WordWrap := False;
  FResponseMemo.Font.Name := 'Consolas';
  FResponseMemo.Font.Size := 9;
end;

procedure TfrmAIAssistant.ConfigClick(Sender: TObject);
var
  Dlg: TfrmAIConfig;
begin
  Dlg := TfrmAIConfig.Create(nil);
  try
    Dlg.APIKeyEdit.Text := FAPIKey;
    Dlg.ModelEdit.Text := FModel;
    if Dlg.ShowModal = mrOk then
    begin
      FAPIKey := Trim(Dlg.APIKeyEdit.Text);
      FModel := Trim(Dlg.ModelEdit.Text);
      if FModel = '' then
        FModel := DefaultModel;
      SaveConfig(FAPIKey, FModel);
      FStatusLabel.Caption := IfThen(FAPIKey = '', 'Configure a API key antes de usar.', 'Pronto.');
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrmAIAssistant.SendClick(Sender: TObject);
var
  Content, Selection: string;
begin
  if FAPIKey = '' then
  begin
    MessageDlg('Configure primeiro a API key da Anthropic.', mtWarning, [mbOK], 0);
    ConfigClick(nil);
    Exit;
  end;
  if Trim(FPromptMemo.Text) = '' then
  begin
    MessageDlg('Escreva um pedido/prompt.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Content := FPromptMemo.Text;
  if FIncludeSelectionCheck.Checked then
  begin
    Selection := GetSelectedText(GetActiveSourceEditor);
    if Selection <> '' then
      Content := Content + sLineBreak + sLineBreak + '---' + sLineBreak +
        'Código selecionado no editor:' + sLineBreak + '```' + sLineBreak + Selection + sLineBreak + '```';
  end;

  FSendButton.Enabled := False;
  FStatusLabel.Caption := 'A contactar a API da Anthropic...';
  FResponseMemo.Text := '';
  SendRequest(FAPIKey, FModel, Content,
    procedure(AText: string; ASuccess: Boolean)
    begin
      HandleResponse(AText, ASuccess);
    end);
end;

procedure TfrmAIAssistant.HandleResponse(const AText: string; ASuccess: Boolean);
begin
  FSendButton.Enabled := True;
  if ASuccess then
  begin
    FResponseMemo.Text := AText;
    FStatusLabel.Caption := 'Resposta recebida.';
  end
  else
  begin
    FResponseMemo.Text := AText;
    FStatusLabel.Caption := 'Falhou. Ver detalhes na resposta.';
  end;
end;

procedure TfrmAIAssistant.InsertClick(Sender: TObject);
begin
  if Trim(FResponseMemo.Text) = '' then
    Exit;
  InsertTextAtCursor(FResponseMemo.Text);
end;

procedure TfrmAIAssistant.ReplaceClick(Sender: TObject);
begin
  if Trim(FResponseMemo.Text) = '' then
    Exit;
  ReplaceSelectedText(FResponseMemo.Text);
end;

procedure ShowAIAssistant;
begin
  if AIForm = nil then
    AIForm := TfrmAIAssistant.Create(Application);
  AIForm.Show;
  AIForm.BringToFront;
end;

finalization
  FreeAndNil(AIForm);

end.
