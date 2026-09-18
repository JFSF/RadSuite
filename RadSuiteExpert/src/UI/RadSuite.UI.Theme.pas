unit RadSuite.UI.Theme;

interface

uses
  System.UITypes, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls,
  Vcl.Graphics;

const
  // Accent color shared by every RadSuite tool window: a calm blue-teal,
  // legible on both light and dark VCL styles.
  RadSuiteAccentColor: TColor = $00DF6C2D;
  RadSuiteMutedTextColor: TColor = $00888888;
  RadSuiteFontName = 'Segoe UI';
  RadSuiteFontSize = 9;

/// <summary>Applies the shared font/position convention to a tool form.</summary>
procedure ApplyRadSuiteStyle(AForm: TCustomForm);

/// <summary>
///   Creates the standard RadSuite header bar (icon-less title + subtitle,
///   accent-colored bottom rule) docked to the top of the form and returns
///   the first free Y coordinate below it, so callers can lay out the rest
///   of the form's controls starting from there.
/// </summary>
function AddRadSuiteHeader(AForm: TForm; const ATitle, ASubtitle: string): Integer;

implementation

function AddRadSuiteHeader(AForm: TForm; const ATitle, ASubtitle: string): Integer;
var
  HeaderPanel: TPanel;
  Rule: TPanel;
  TitleLabel: TLabel;
  SubtitleLabel: TLabel;
begin
  HeaderPanel := TPanel.Create(AForm);
  HeaderPanel.Parent := AForm;
  HeaderPanel.Align := alTop;
  HeaderPanel.Height := 56;
  HeaderPanel.BevelOuter := bvNone;
  HeaderPanel.ParentBackground := True;

  TitleLabel := TLabel.Create(AForm);
  TitleLabel.Parent := HeaderPanel;
  TitleLabel.Left := 12;
  TitleLabel.Top := 8;
  TitleLabel.Font.Name := RadSuiteFontName;
  TitleLabel.Font.Size := RadSuiteFontSize + 3;
  TitleLabel.Font.Style := [fsBold];
  TitleLabel.Caption := ATitle;

  SubtitleLabel := TLabel.Create(AForm);
  SubtitleLabel.Parent := HeaderPanel;
  SubtitleLabel.Left := 12;
  SubtitleLabel.Top := TitleLabel.Top + TitleLabel.Height + 2;
  SubtitleLabel.Font.Name := RadSuiteFontName;
  SubtitleLabel.Font.Size := RadSuiteFontSize;
  SubtitleLabel.Font.Color := RadSuiteMutedTextColor;
  SubtitleLabel.Caption := ASubtitle;

  Rule := TPanel.Create(AForm);
  Rule.Parent := HeaderPanel;
  Rule.Align := alBottom;
  Rule.Height := 2;
  Rule.BevelOuter := bvNone;
  Rule.Color := RadSuiteAccentColor;

  Result := HeaderPanel.Height + 12;
end;

procedure ApplyRadSuiteStyle(AForm: TCustomForm);
begin
  AForm.Font.Name := RadSuiteFontName;
  AForm.Font.Size := RadSuiteFontSize;
  AForm.Position := poScreenCenter;
end;

end.
