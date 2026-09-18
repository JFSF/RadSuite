unit RadSuite.Expert.Register;

interface

implementation

uses
  ToolsAPI,
  RadSuite.Expert.Wizard,
  RadSuite.Expert.AboutBox;

initialization
  RegisterPackageWizard(TRadSuiteWizard.Create);
  RegisterAboutBox;
finalization
  UnregisterAboutBox;
end.
