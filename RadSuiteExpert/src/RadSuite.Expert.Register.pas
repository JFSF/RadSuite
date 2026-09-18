unit RadSuite.Expert.Register;

interface

implementation

uses
  System.SysUtils,
  ToolsAPI,
  RadSuite.Expert.Wizard,
  RadSuite.Expert.AboutBox,
  RadSuite.Expert.MainMenu;

var
  MenuController: TRadSuiteMenuController;

initialization
  RegisterPackageWizard(TRadSuiteWizard.Create);
  RegisterAboutBox;
  MenuController := TRadSuiteMenuController.Create;
finalization
  FreeAndNil(MenuController);
  UnregisterAboutBox;
end.
