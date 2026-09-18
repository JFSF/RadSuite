unit RadSuite.Tools.PEInformation;

interface

procedure ShowPEInformation;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  System.Math, System.StrUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  RadSuite.UI.Theme;

type
  TRSImageDosHeader = packed record
    e_magic: Word;
    e_cblp, e_cp, e_crlc, e_cparhdr, e_minalloc, e_maxalloc: Word;
    e_ss, e_sp, e_csum, e_ip, e_cs, e_lfarlc, e_ovno: Word;
    e_res: array[0..3] of Word;
    e_oemid, e_oeminfo: Word;
    e_res2: array[0..9] of Word;
    e_lfanew: Int32;
  end;

  TRSImageDataDirectory = packed record
    VirtualAddress: UInt32;
    Size: UInt32;
  end;

  TRSImageFileHeader = packed record
    Machine: Word;
    NumberOfSections: Word;
    TimeDateStamp: UInt32;
    PointerToSymbolTable: UInt32;
    NumberOfSymbols: UInt32;
    SizeOfOptionalHeader: Word;
    Characteristics: Word;
  end;

  TRSImageOptionalHeader32 = packed record
    Magic: Word;
    MajorLinkerVersion, MinorLinkerVersion: Byte;
    SizeOfCode, SizeOfInitializedData, SizeOfUninitializedData: UInt32;
    AddressOfEntryPoint, BaseOfCode, BaseOfData, ImageBase: UInt32;
    SectionAlignment, FileAlignment: UInt32;
    MajorOperatingSystemVersion, MinorOperatingSystemVersion: Word;
    MajorImageVersion, MinorImageVersion: Word;
    MajorSubsystemVersion, MinorSubsystemVersion: Word;
    Win32VersionValue, SizeOfImage, SizeOfHeaders, CheckSum: UInt32;
    Subsystem, DllCharacteristics: Word;
    SizeOfStackReserve, SizeOfStackCommit: UInt32;
    SizeOfHeapReserve, SizeOfHeapCommit: UInt32;
    LoaderFlags, NumberOfRvaAndSizes: UInt32;
    DataDirectory: array[0..15] of TRSImageDataDirectory;
  end;

  TRSImageOptionalHeader64 = packed record
    Magic: Word;
    MajorLinkerVersion, MinorLinkerVersion: Byte;
    SizeOfCode, SizeOfInitializedData, SizeOfUninitializedData: UInt32;
    AddressOfEntryPoint, BaseOfCode: UInt32;
    ImageBase: UInt64;
    SectionAlignment, FileAlignment: UInt32;
    MajorOperatingSystemVersion, MinorOperatingSystemVersion: Word;
    MajorImageVersion, MinorImageVersion: Word;
    MajorSubsystemVersion, MinorSubsystemVersion: Word;
    Win32VersionValue, SizeOfImage, SizeOfHeaders, CheckSum: UInt32;
    Subsystem, DllCharacteristics: Word;
    SizeOfStackReserve, SizeOfStackCommit: UInt64;
    SizeOfHeapReserve, SizeOfHeapCommit: UInt64;
    LoaderFlags, NumberOfRvaAndSizes: UInt32;
    DataDirectory: array[0..15] of TRSImageDataDirectory;
  end;

  TRSImageSectionHeader = packed record
    Name: array[0..7] of AnsiChar;
    VirtualSize: UInt32;
    VirtualAddress: UInt32;
    SizeOfRawData: UInt32;
    PointerToRawData: UInt32;
    PointerToRelocations: UInt32;
    PointerToLinenumbers: UInt32;
    NumberOfRelocations: Word;
    NumberOfLinenumbers: Word;
    Characteristics: UInt32;
  end;

  TRSImageImportDescriptor = packed record
    OriginalFirstThunk: UInt32;
    TimeDateStamp: UInt32;
    ForwarderChain: UInt32;
    Name: UInt32;
    FirstThunk: UInt32;
  end;

  TRSImageExportDirectory = packed record
    Characteristics: UInt32;
    TimeDateStamp: UInt32;
    MajorVersion, MinorVersion: Word;
    Name: UInt32;
    Base: UInt32;
    NumberOfFunctions: UInt32;
    NumberOfNames: UInt32;
    AddressOfFunctions: UInt32;
    AddressOfNames: UInt32;
    AddressOfNameOrdinals: UInt32;
  end;

const
  IMAGE_DIRECTORY_ENTRY_EXPORT = 0;
  IMAGE_DIRECTORY_ENTRY_IMPORT = 1;
  IMAGE_ORDINAL_FLAG32 = UInt32($80000000);
  IMAGE_ORDINAL_FLAG64 = UInt64($8000000000000000);

function ReadStruct<T>(const Buffer: TBytes; Offset: Int64; out Value: T): Boolean;
begin
  Result := (Offset >= 0) and (Offset + SizeOf(T) <= Length(Buffer));
  if Result then
    Move(Buffer[Offset], Value, SizeOf(T));
end;

function ReadCString(const Buffer: TBytes; Offset: Int64): string;
var
  P: Int64;
begin
  Result := '';
  if (Offset < 0) or (Offset >= Length(Buffer)) then
    Exit;
  P := Offset;
  while (P < Length(Buffer)) and (Buffer[P] <> 0) do
    Inc(P);
  SetString(Result, PAnsiChar(@Buffer[Offset]), Integer(P - Offset));
end;

function RvaToOffset(const Sections: TArray<TRSImageSectionHeader>; RVA: UInt32; out Offset: Int64): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Sections) do
    if (RVA >= Sections[I].VirtualAddress) and
       (RVA < Sections[I].VirtualAddress + Max(Sections[I].VirtualSize, Sections[I].SizeOfRawData)) then
    begin
      Offset := Sections[I].PointerToRawData + (RVA - Sections[I].VirtualAddress);
      Exit(True);
    end;
end;

procedure AppendSection(Lines: TStrings; const ATitle: string);
begin
  Lines.Add('');
  Lines.Add(ATitle);
  Lines.Add(StringOfChar('-', Length(ATitle)));
end;

procedure BuildReport(const FileName: string; Lines: TStrings);
var
  Buffer: TBytes;
  Dos: TRSImageDosHeader;
  Signature: UInt32;
  NtHeaderOffset, OptHeaderOffset, SectionOffset: Int64;
  FileHdr: TRSImageFileHeader;
  MagicWord: Word;
  Is64: Boolean;
  Opt32: TRSImageOptionalHeader32;
  Opt64: TRSImageOptionalHeader64;
  DataDirs: array[0..15] of TRSImageDataDirectory;
  Sections: TArray<TRSImageSectionHeader>;
  Sec: TRSImageSectionHeader;
  I, J: Integer;
  ExportDirRVA, ImportDirRVA: UInt32;
  ExportOffset: Int64;
  ExpDir: TRSImageExportDirectory;
  NameRVA: UInt32;
  NameOffset: Int64;
  ImportOffset: Int64;
  ImpDesc: TRSImageImportDescriptor;
  ThunkOffset: Int64;
  Thunk32: UInt32;
  HintNameOffset: Int64;
  FuncName: string;
begin
  Lines.Clear;
  try
    Buffer := TFile.ReadAllBytes(FileName);
  except
    on E: Exception do
    begin
      Lines.Add('Erro ao ler o ficheiro: ' + E.Message);
      Exit;
    end;
  end;

  if not ReadStruct(Buffer, 0, Dos) or (Dos.e_magic <> $5A4D) then
  begin
    Lines.Add('Ficheiro inválido: assinatura MZ (DOS) não encontrada.');
    Exit;
  end;

  NtHeaderOffset := Dos.e_lfanew;
  if not ReadStruct(Buffer, NtHeaderOffset, Signature) or (Signature <> $00004550) then
  begin
    Lines.Add('Ficheiro inválido: assinatura PE não encontrada (não é um EXE/DLL/BPL Win32/Win64).');
    Exit;
  end;

  if not ReadStruct(Buffer, NtHeaderOffset + 4, FileHdr) then
  begin
    Lines.Add('Ficheiro truncado: não foi possível ler o File Header.');
    Exit;
  end;

  OptHeaderOffset := NtHeaderOffset + 4 + SizeOf(FileHdr);
  ReadStruct(Buffer, OptHeaderOffset, MagicWord);
  Is64 := MagicWord = $020B;

  AppendSection(Lines, 'Cabeçalho');
  Lines.Add(Format('Ficheiro:            %s', [FileName]));
  Lines.Add(Format('Tamanho:             %d bytes', [Length(Buffer)]));
  Lines.Add(Format('Arquitetura:         %s', [IfThen(Is64, 'PE32+ (64-bit)', 'PE32 (32-bit)')]));
  case FileHdr.Machine of
    $014C: Lines.Add('Machine:             IMAGE_FILE_MACHINE_I386');
    $8664: Lines.Add('Machine:             IMAGE_FILE_MACHINE_AMD64');
    $01C4: Lines.Add('Machine:             IMAGE_FILE_MACHINE_ARMNT');
    $AA64: Lines.Add('Machine:             IMAGE_FILE_MACHINE_ARM64');
  else
    Lines.Add(Format('Machine:             $%.4x', [FileHdr.Machine]));
  end;
  Lines.Add(Format('Nº de secções:       %d', [FileHdr.NumberOfSections]));
  try
    Lines.Add(Format('Compilado em:        %s UTC', [DateTimeToStr(UnixToDateTime(FileHdr.TimeDateStamp))]));
  except
    // TimeDateStamp fora do intervalo suportado; ignora.
  end;
  Lines.Add(Format('Characteristics:     $%.4x%s', [FileHdr.Characteristics,
    IfThen((FileHdr.Characteristics and $2000) <> 0, ' (DLL)', '')]));

  if Is64 then
  begin
    ReadStruct(Buffer, OptHeaderOffset, Opt64);
    DataDirs := Opt64.DataDirectory;
    Lines.Add(Format('EntryPoint (RVA):    $%.8x', [Opt64.AddressOfEntryPoint]));
    Lines.Add(Format('ImageBase:           $%.16x', [Opt64.ImageBase]));
    Lines.Add(Format('Subsystem:           %d', [Opt64.Subsystem]));
    Lines.Add(Format('SizeOfImage:         %d bytes', [Opt64.SizeOfImage]));
  end
  else
  begin
    ReadStruct(Buffer, OptHeaderOffset, Opt32);
    DataDirs := Opt32.DataDirectory;
    Lines.Add(Format('EntryPoint (RVA):    $%.8x', [Opt32.AddressOfEntryPoint]));
    Lines.Add(Format('ImageBase:           $%.8x', [Opt32.ImageBase]));
    Lines.Add(Format('Subsystem:           %d', [Opt32.Subsystem]));
    Lines.Add(Format('SizeOfImage:         %d bytes', [Opt32.SizeOfImage]));
  end;

  SectionOffset := OptHeaderOffset + FileHdr.SizeOfOptionalHeader;
  SetLength(Sections, FileHdr.NumberOfSections);
  AppendSection(Lines, Format('Secções (%d)', [FileHdr.NumberOfSections]));
  Lines.Add('Nome      VirtAddr   VirtSize   RawSize    RawOffset  Flags');
  for I := 0 to FileHdr.NumberOfSections - 1 do
  begin
    if not ReadStruct(Buffer, SectionOffset + I * SizeOf(TRSImageSectionHeader), Sec) then
      Break;
    Sections[I] := Sec;
    Lines.Add(Format('%-9s $%.8x $%.8x $%.8x $%.8x $%.8x',
      [string(Sec.Name), Sec.VirtualAddress, Sec.VirtualSize, Sec.SizeOfRawData,
       Sec.PointerToRawData, Sec.Characteristics]));
  end;

  // Import table
  ImportDirRVA := DataDirs[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
  if (ImportDirRVA <> 0) and RvaToOffset(Sections, ImportDirRVA, ImportOffset) then
  begin
    AppendSection(Lines, 'Imports');
    I := 0;
    while ReadStruct(Buffer, ImportOffset + I * SizeOf(TRSImageImportDescriptor), ImpDesc) and
          ((ImpDesc.OriginalFirstThunk <> 0) or (ImpDesc.Name <> 0) or (ImpDesc.FirstThunk <> 0)) do
    begin
      if RvaToOffset(Sections, ImpDesc.Name, NameOffset) then
        Lines.Add(ReadCString(Buffer, NameOffset) + ':');
      ThunkOffset := 0;
      if not ((ImpDesc.OriginalFirstThunk <> 0) and
              RvaToOffset(Sections, ImpDesc.OriginalFirstThunk, ThunkOffset)) then
        RvaToOffset(Sections, ImpDesc.FirstThunk, ThunkOffset);
      if ThunkOffset > 0 then
      begin
        J := 0;
        while ReadStruct(Buffer, ThunkOffset + J * SizeOf(UInt32), Thunk32) and (Thunk32 <> 0) do
        begin
          if (Thunk32 and IMAGE_ORDINAL_FLAG32) <> 0 then
            Lines.Add(Format('    #%d (por ordinal)', [Thunk32 and $FFFF]))
          else if RvaToOffset(Sections, Thunk32, HintNameOffset) then
          begin
            FuncName := ReadCString(Buffer, HintNameOffset + 2); // salta o campo Hint (Word)
            Lines.Add('    ' + FuncName);
          end;
          Inc(J);
        end;
      end;
      Inc(I);
    end;
  end;

  // Export table
  ExportDirRVA := DataDirs[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;
  if (ExportDirRVA <> 0) and RvaToOffset(Sections, ExportDirRVA, ExportOffset) then
  begin
    if ReadStruct(Buffer, ExportOffset, ExpDir) then
    begin
      AppendSection(Lines, Format('Exports (%d nomes)', [ExpDir.NumberOfNames]));
      if RvaToOffset(Sections, ExpDir.AddressOfNames, NameOffset) then
        for I := 0 to Integer(ExpDir.NumberOfNames) - 1 do
        begin
          if not ReadStruct(Buffer, NameOffset + I * SizeOf(UInt32), NameRVA) then
            Break;
          if RvaToOffset(Sections, NameRVA, HintNameOffset) then
            Lines.Add('  ' + ReadCString(Buffer, HintNameOffset));
        end;
    end;
  end;
end;

type
  TfrmPEInformation = class(TForm)
  private
    FFileEdit: TEdit;
    FReportMemo: TMemo;
    FOpenDialog: TOpenDialog;
    procedure BrowseClick(Sender: TObject);
    procedure AnalyzeClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TfrmPEInformation.Create(AOwner: TComponent);
var
  Top: Integer;
  ToolPanel: TPanel;
  BrowseButton, AnalyzeButton: TButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'PE Information';
  ClientWidth := 680;
  ClientHeight := 560;
  BorderStyle := bsSizeable;
  ApplyRadSuiteStyle(Self);

  Top := AddRadSuiteHeader(Self, 'PE Information',
    'Inspetor de ficheiros PE (EXE/DLL/BPL): headers, secções, imports e exports');

  ToolPanel := TPanel.Create(Self);
  ToolPanel.Parent := Self;
  ToolPanel.Top := Top;
  ToolPanel.Align := alTop;
  ToolPanel.Height := 40;
  ToolPanel.BevelOuter := bvNone;

  FFileEdit := TEdit.Create(Self);
  FFileEdit.Parent := ToolPanel;
  FFileEdit.Left := 12;
  FFileEdit.Top := 8;
  FFileEdit.Width := 460;

  BrowseButton := TButton.Create(Self);
  BrowseButton.Parent := ToolPanel;
  BrowseButton.Caption := 'Procurar...';
  BrowseButton.Left := FFileEdit.Left + FFileEdit.Width + 8;
  BrowseButton.Top := 6;
  BrowseButton.Width := 90;
  BrowseButton.OnClick := BrowseClick;

  AnalyzeButton := TButton.Create(Self);
  AnalyzeButton.Parent := ToolPanel;
  AnalyzeButton.Caption := 'Analisar';
  AnalyzeButton.Left := BrowseButton.Left + BrowseButton.Width + 8;
  AnalyzeButton.Top := 6;
  AnalyzeButton.Width := 90;
  AnalyzeButton.OnClick := AnalyzeClick;

  FReportMemo := TMemo.Create(Self);
  FReportMemo.Parent := Self;
  FReportMemo.Align := alClient;
  FReportMemo.ScrollBars := ssBoth;
  FReportMemo.ReadOnly := True;
  FReportMemo.WordWrap := False;
  FReportMemo.Font.Name := 'Consolas';
  FReportMemo.Font.Size := 9;

  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.Filter := 'Executáveis e bibliotecas (*.exe;*.dll;*.bpl)|*.exe;*.dll;*.bpl|Todos os ficheiros (*.*)|*.*';
end;

procedure TfrmPEInformation.BrowseClick(Sender: TObject);
begin
  if FOpenDialog.Execute then
    FFileEdit.Text := FOpenDialog.FileName;
end;

procedure TfrmPEInformation.AnalyzeClick(Sender: TObject);
begin
  if FFileEdit.Text = '' then
  begin
    MessageDlg('Escolha primeiro um ficheiro.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if not TFile.Exists(FFileEdit.Text) then
  begin
    MessageDlg('O ficheiro indicado não existe.', mtError, [mbOK], 0);
    Exit;
  end;
  BuildReport(FFileEdit.Text, FReportMemo.Lines);
end;

procedure ShowPEInformation;
var
  Form: TfrmPEInformation;
begin
  Form := TfrmPEInformation.Create(nil);
  Form.Show;
end;

end.
