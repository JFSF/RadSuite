unit RadSuite.Expert.AboutBox;

interface

procedure RegisterAboutBox;
procedure UnregisterAboutBox;

implementation

uses
  System.SysUtils, ToolsAPI;

var
  AboutBoxIndex: Integer = -1;

procedure RegisterAboutBox;
var
  AboutBoxServices: IOTAAboutBoxServices;
begin
  if Supports(BorlandIDEServices, IOTAAboutBoxServices, AboutBoxServices) then
    AboutBoxIndex := AboutBoxServices.AddPluginInfo(
      'RadSuite Expert',
      'Toolkit de produtividade para o Delphi 13: Grep Search & Replace, Uses Clause ' +
      'Manager, Class Browser, Unit Dependencies, Code Librarian, AI Assistant, PE ' +
      'Information, ASCII Chart e Clean Directories.' + sLineBreak +
      'https://github.com/jfsf/radsuite',
      0);
end;

procedure UnregisterAboutBox;
var
  AboutBoxServices: IOTAAboutBoxServices;
begin
  if (AboutBoxIndex <> -1) and Supports(BorlandIDEServices, IOTAAboutBoxServices, AboutBoxServices) then
  begin
    AboutBoxServices.RemovePluginInfo(AboutBoxIndex);
    AboutBoxIndex := -1;
  end;
end;

end.
