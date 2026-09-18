unit RadSuite.Expert.Wizard;

interface

uses
  ToolsAPI;

type
  TRadSuiteWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  public
    // IOTAWizard
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    // IOTAMenuWizard
    function GetMenuText: string;
  end;

implementation

uses
  Vcl.Dialogs;

{ TRadSuiteWizard }

function TRadSuiteWizard.GetIDString: string;
begin
  Result := 'JFSF.RadSuite.Expert.Wizard';
end;

function TRadSuiteWizard.GetName: string;
begin
  Result := 'RadSuite Expert';
end;

function TRadSuiteWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

function TRadSuiteWizard.GetMenuText: string;
begin
  Result := 'RadSuite Expert...';
end;

procedure TRadSuiteWizard.Execute;
begin
  ShowMessage('RadSuite Expert instalado com sucesso no Delphi 13!');
end;

end.
