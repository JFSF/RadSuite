unit RadSuite.Expert.AboutBox;

interface

procedure RegisterAboutBox;
procedure UnregisterAboutBox;

implementation

uses
  ToolsAPI;

var
  AboutBoxIndex: Integer = -1;

procedure RegisterAboutBox;
var
  AboutBoxServices: IOTAAboutBoxServices;
begin
  if Supports(BorlandIDEServices, IOTAAboutBoxServices, AboutBoxServices) then
    AboutBoxIndex := AboutBoxServices.AddPluginInfo(
      'RadSuite Expert',
      'Expert/Wizard personalizado para o Delphi 13.' + sLineBreak +
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
