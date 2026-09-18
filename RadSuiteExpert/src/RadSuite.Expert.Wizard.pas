unit RadSuite.Expert.Wizard;

interface

uses
  ToolsAPI;

type
  TRadSuiteWizard = class(TNotifierObject, IOTAWizard)
  public
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

implementation

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

procedure TRadSuiteWizard.Execute;
begin
  // Sem ação direta: as ferramentas são acedidas pelo menu "RadSuite" da IDE
  // (ver RadSuite.Expert.MainMenu). Este wizard existe para satisfazer o
  // registo mínimo exigido pela Open Tools API.
end;

end.
