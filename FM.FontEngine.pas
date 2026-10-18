unit FM.FontEngine;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Winapi.GDIPOBJ, Winapi.GDIPAPI,
  System.SysUtils, System.Classes, System.IOUtils, System.Win.Registry, Vcl.Forms;

type
  TFontFilterType = (ftAll, ftMonospace, ftBitmap);

type
  TFontEngine = class

  private
    // Interne Hilfsmethode zur Typ-Erkennung
    class procedure GetFontProperties(const FontName: string;
                                      var IsMono, IsBitmap: Boolean);
    class function GetInternalList: TStringList;

  public
    // Erweiterte GetFonts-Methode mit Filter-Parametern
    class procedure GetFontsFiltered(TargetList: TStrings;
                                     const SearchText: string;
                                     FilterType: TFontFilterType);

    // Wichtige System-Fonts
    class function IsSystemProtectedFont(const FontName: string): Boolean;
    // Holt die schreibgeschützte Liste für die Benutzeroberfläche (Memos, Grids)
    class function GetFonts: TStrings;
    // Zwingt Windows und die Engine, die installierten Schriften frisch einzulesen
    class procedure RefreshFonts;

    // Lokale Hilfsmethoden des Hauptprogramms (Instanz 1)
    class function GetFullFontNameFromSystem(const TruncatedName: string): string;
    class function GetFontFamilyNameGDIP(const FontFilePath: string): string;
    class function GetExactFontFileName(const FontNameFromList: string): string;
    class function RunAsAdmin(const FormHandle: HWND;
                              const Param, Argument: string): Boolean;
    class function TryReleaseFontFile(const FontName: string): Boolean;
    class function InstallFontFamily(const FormHandle: HWND;
                                     const FontFilePath: string;
                                     out FontName: string): Boolean;
    class function UninstallFontFamily(const FormHandle: HWND;
                                       const FontNameFromList: string): Boolean;

    // Versteckte administrative Kern-Operationen (Instanz 2)
    class function SilentInstall(const SourcePath: string): Boolean;
    class function SilentUninstall(const RegistryFontName: string): Boolean;
  end;

implementation

uses FM.SysUtils;

var
  FFontList: TStringList = nil; // Interner Speicher für die Schriftartenliste
  GdiplusToken: ULONG_PTR;      // Hauptschlüssel für Grafikbibliothek GDI+

{ TFontEngine }

class procedure TFontEngine.GetFontsFiltered(TargetList: TStrings;
                                             const SearchText: string;
                                             FilterType: TFontFilterType);
var
  I: Integer;
  FontName, UpperSearch: string;
  IsMono, IsBitmap: Boolean;
  SourceList: TStrings;
begin
  TargetList.BeginUpdate;
  try
    TargetList.Clear;
    SourceList := GetFonts; // Hol die ungefilterte Master-Liste aus der Engine
    UpperSearch := UpperCase(Trim(SearchText));

    for I := 0 to SourceList.Count - 1 do
    begin
      FontName := SourceList[I];

      // 1: Suche-Filter: Wenn ein Suchtext da ist, muss er im Namen vorkommen
      if (UpperSearch <> '') and (Pos(UpperSearch, UpperCase(FontName)) <> 1) then
        Continue;

      // 2: Anzeige-Filter (Monospace / Rasterschriften)
      if FilterType <> ftAll then
      begin
        GetFontProperties(FontName, IsMono, IsBitmap);
        if (FilterType = ftMonospace) and not IsMono then Continue;
        if (FilterType = ftBitmap) and not IsBitmap then Continue;
      end;

      // Wenn alle Kriterien erfüllt sind, ab in die Liste
      TargetList.Add(FontName);
    end;
  finally
    TargetList.EndUpdate;
  end;
end;

class procedure TFontEngine.GetFontProperties(const FontName: string;
                                              var IsMono, IsBitmap: Boolean);
var
  DC: HDC;
  LogFont: TLogFont;
  FontHandle, OldFont: HFONT;
  TextMetric: TTextMetric;
begin
  IsMono := False;
  IsBitmap := False;

  DC := GetDC(0);
  try
    FillChar(LogFont, SizeOf(LogFont), 0);
    // Wir nutzen hier funktionierende GDI-Namenshintertür!
    StrPLCopy(LogFont.lfFaceName, GetFullFontNameFromSystem(FontName), LF_FACESIZE - 1);

    FontHandle := CreateFontIndirect(LogFont);
    if FontHandle <> 0 then
    begin
      OldFont := SelectObject(DC, FontHandle);
      if GetTextMetrics(DC, TextMetric) then
      begin
        // TMPF_FIXED_PITCH ist bei Fixed-Pitch-Fonts paradoxerweise 0!
        IsMono := (TextMetric.tmPitchAndFamily and TMPF_FIXED_PITCH) = 0;
        // Rasterschriften (Bitmap) haben das Bit TMPF_VECTOR nicht gesetzt
        IsBitmap := (TextMetric.tmPitchAndFamily and TMPF_VECTOR) = 0;
      end;
      SelectObject(DC, OldFont);
      DeleteObject(FontHandle);
    end;
  finally
    ReleaseDC(0, DC);
  end;
end;

class function TFontEngine.IsSystemProtectedFont(const FontName: string): Boolean;
const
  // Die absolut kritischen Windows-Core-Fonts
  BLACKLIST: array[0..15] of string = (
    'Segoe UI', 'Segoe MDL2 Assets', 'Segoe Fluent Icons',    // Windows 10/11 UI
    'Arial', 'Calibri', 'Cambria', 'Consolas', 'Courier New', // Office & Terminal
    'Times New Roman', 'MS Sans Serif', 'MS Serif', 'Marlett',// Windows Legacy
    'Malgun Gothic', 'Microsoft YaHei', 'Microsoft JhengHei', // Asiatische Sys.-Schriften
    'Fixedsys'                                                // Editor-Standard-Font
  );
var
  I: Integer;
  UpperFontName: string;
begin
  Result := False;
  UpperFontName := UpperCase(Trim(FontName));

  for I := Low(BLACKLIST) to High(BLACKLIST) do
  begin
    // Prüft, ob der Name mit einem geschützten Begriff
    // beginnt (z.B. "Segoe UI Semibold" -> geschützt)
    if Pos(UpperCase(BLACKLIST[I]), UpperFontName) > 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

// Singleton-Verwalter für den internen StringList-Speicher.
// Preventiert Zirkelbezüge beim Start.
class function TFontEngine.GetInternalList: TStringList;
begin
  if FFontList = nil then
  begin
    FFontList := TStringList.Create;
    RefreshFonts;
  end;
  Result := FFontList;
end;

// Liest alle installierten System-Schriftarten über die VCL frisch aus.
class procedure TFontEngine.RefreshFonts;
var
  I: Integer;
  InterneListe: TStringList;
begin
  Screen.ResetFonts; // Windows-GDI-Cache zur Aktualisierung zwingen
  InterneListe := GetInternalList;

  InterneListe.BeginUpdate;
  try
    InterneListe.Clear;
    for I := 0 to Screen.Fonts.Count - 1 do
      InterneListe.Add(Screen.Fonts[I]);
  finally
    InterneListe.EndUpdate;
  end;
end;

class function TFontEngine.GetFonts: TStrings;
begin
  Result := GetInternalList;
end;

// Verwaltet die permanente Installation:
// Prüft auf Dubletten und delegiert an den Admin-Prozess.
class function TFontEngine.InstallFontFamily(const FormHandle: HWND;
                                             const FontFilePath:
                                             string; out FontName: string): Boolean;
begin
  Result := False;
  FontName := GetFontFamilyNameGDIP(FontFilePath);

  // Vorab-Prüfung, um Doppelinstallationen zu vermeiden
  if GetInternalList.IndexOf(FontName) > -1 then
  begin
    FontName := 'ALREADY_INSTALLED';
    Exit;
  end;

  // Admin-Ghostprozess starten
  if RunAsAdmin(FormHandle, '--install', FontFilePath) then
  begin
    // Broadcast-Signal senden: Informiert das Betriebssystem über die neue Schriftart
    SendMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
    RefreshFonts;
    Result := True;
  end;
end;

// Deinstallation: Hebt lokale GDI-Sperren auf und
// startet die Admin-Löschung.
class function TFontEngine.UninstallFontFamily(const FormHandle: HWND;
                                               const FontNameFromList: string): Boolean;
var
  FontsFolder, SuchMaske, GefundeneDatei, FullFontPath: string;
  SR: TSearchRec;
  I: Integer;
begin
  Result := False;

  // SYSTEM-SCHUTZSCHILD: Sofortiger Abbruch, falls auf der Blacklist
  if IsSystemProtectedFont(FontNameFromList) then
    Exit; // Gibt False zurück

  FontsFolder := IncludeTrailingPathDelimiter(FM.SysUtils.GetWindowsFontsPath);

  // Erstes Wort extrahieren, um Abschneidungen im UI-Steuerelement abzufangen
  if Pos(' ', FontNameFromList) > 0 then
    SuchMaske := Copy(FontNameFromList, 1, Pos(' ', FontNameFromList) - 1)
  else
    SuchMaske := FontNameFromList;

  // .ttf-Datei auf der Festplatte via Wildcard ermitteln
  GefundeneDatei := '';
  if FindFirst(FontsFolder + SuchMaske + '*.ttf', faAnyFile, SR) = 0 then
  begin
    try
      GefundeneDatei := SR.Name;
    finally
      FindClose(SR);
    end;
  end;

  // Wenn die Datei gefunden wurde, entladen wir sie vorab aus dem RAM des Hauptprogramms
  if GefundeneDatei <> '' then
  begin
    FullFontPath := FontsFolder + GefundeneDatei;
    RemoveFontResourceEx(PChar(FullFontPath), FR_PRIVATE, nil);
    RemoveFontResource(PChar(FullFontPath));
    SendMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);

    // Admin-Löschung mit dem Dateinamen aufrufen
    if RunAsAdmin(FormHandle, '--uninstall', GefundeneDatei) then
    begin
      RefreshFonts;

      // Zusätzliche visuelle Echtzeit-Bereinigung der internen Liste (Case-Insensitive)
      GetInternalList.BeginUpdate;
      try
        var ObererSuchBegriff := UpperCase(SuchMaske);
        for I := GetInternalList.Count - 1 downto 0 do
        begin
          if Pos(ObererSuchBegriff, UpperCase(GetInternalList[I])) > 0 then
            GetInternalList.Delete(I);
        end;
      finally
        GetInternalList.EndUpdate;
      end;
      Result := True;
    end;
  end;
end;

// Gibt den vollständigen Fontnamen zurück
class function TFontEngine.GetFullFontNameFromSystem(const TruncatedName: string): string;
var
  DC: HDC;
  LogFont: TLogFont;
  HFnt, HOldFnt: HFONT;
  Buffer: array[0..255] of Char; // Großzügiger Puffer für den ungeschnittenen Namen
begin
  Result := '';

  // 1: Einen unsichtbaren Grafik-Kontext von Windows anfordern
  DC := GetDC(0);
  if DC <> 0 then
  begin
    try
      // 2: Die Windows-Schriftartenstruktur mit dem abgeschnittenen Namen füttern
      ZeroMemory(@LogFont, SizeOf(TLogFont));
      LogFont.lfCharSet := DEFAULT_CHARSET;

      // Kopiert den Text sicher hinein (maximal 31 Zeichen)
      StrPLCopy(LogFont.lfFaceName, TruncatedName, LF_FACESIZE - 1);

      // 3: Den Font im Windows-Speicher erzeugen und aktivieren
      HFnt := CreateFontIndirect(LogFont);
      if HFnt <> 0 then
      begin
        HOldFnt := SelectObject(DC, HFnt);
        try
          // 4: Windows soll den ungeschnittenen Namen in den Puffer zu schreiben!
          ZeroMemory(@Buffer, SizeOf(Buffer));
          if GetTextFace(DC, Length(Buffer), Buffer) > 0 then
          begin
            Result := string(Buffer);
          end;
        finally
          // 5: Speicher im System freigeben
          SelectObject(DC, HOldFnt);
          DeleteObject(HFnt);
        end;
      end;
    finally
      ReleaseDC(0, DC);
    end;
  end;

  // Sicherheits-Fallback: Falls Windows streikt, nehmen wir den alten Namen
  if Result = '' then
    Result := TruncatedName;
end;


// Extrahiert den ungeschnittenen Familiennamen mittels nativer,
// flacher Windows-GDI+-Schnittstellen.
class function TFontEngine.GetFontFamilyNameGDIP(const FontFilePath: string): string;
var
  NativeCollection: GpFontCollection;
  NumFamilies: Integer;
  FoundFamilies: Integer;
  NativeFamilies: array of GpFontFamily;
  FriendlyName: array[0..LF_FACESIZE] of WideChar;
begin
  Result := '';
  if not FileExists(FontFilePath) then Exit;

  NativeCollection := nil;
  NumFamilies := 0;

  if GdipNewPrivateFontCollection(NativeCollection) = Ok then
  begin
    try
      if GdipPrivateAddFontFile(NativeCollection, PWideChar(WideString(FontFilePath))) = Ok then
      begin
        if GdipGetFontCollectionFamilyCount(NativeCollection, NumFamilies) = Ok then
        begin
          if NumFamilies > 0 then
          begin
            SetLength(NativeFamilies, NumFamilies);
            FoundFamilies := 0;

            if GdipGetFontCollectionFamilyList(NativeCollection, NumFamilies, NativeFamilies, FoundFamilies) = Ok then
            begin
              if FoundFamilies > 0 then
              begin
                FillChar(FriendlyName, SizeOf(FriendlyName), 0);
                // Typensicherer Zugriff auf das erste Element des nativen Zeiger-Arrays
                if GdipGetFamilyName(NativeFamilies[0], FriendlyName, 0) = Ok then
                begin
                  Result := string(FriendlyName);
                end;
              end;
            end;
          end;
        end;
      end;
    finally
      GdipDeletePrivateFontCollection(NativeCollection);
    end;
  end;

  if Result = '' then
    Result := ChangeFileExt(ExtractFileName(FontFilePath), '');
end;

// Gibt den Pfad und Dateinamen von FontFileNameFromList zurück (c:\windows\fonts\*.*)
class function TFontEngine.GetExactFontFileName(const FontNameFromList: string): string;
var
  FontsFolder, SuchMaske: string;
  SR: TSearchRec;
begin
  Result := '';
  FontsFolder := IncludeTrailingPathDelimiter(FM.SysUtils.GetWindowsFontsPath);

  // 1: Wir holen uns das erste Wort (z. B. "Bitcount")
  if Pos(' ', FontNameFromList) > 0 then
    SuchMaske := Copy(FontNameFromList, 1, Pos(' ', FontNameFromList) - 1)
  else
    SuchMaske := FontNameFromList;

  // 2: Ordner mit * durchsuchen (entspricht "dir bi*.* /b" im CMD)
  if FindFirst(FontsFolder + SuchMaske + '*.ttf', faAnyFile, SR) = 0 then
  begin
    try
      // Windows liefert uns das riesige "BitcountInk-VariableFont..." zurück
      Result := SR.Name;
    finally
      FindClose(SR);
    end;
  end;
end;


// Ruft sich selbst unsichtbar als Administrator auf (UAC Elevation)
// und wartet blockierungsfrei.
class function TFontEngine.RunAsAdmin(const FormHandle: HWND;
                                      const Param, Argument: string): Boolean;
var
  Sei: TShellExecuteInfo;
  ExitCodeProcess, WaitResult: DWORD;
begin
  Result := False;
  ZeroMemory(@Sei, SizeOf(Sei));
  Sei.cbSize := SizeOf(TShellExecuteInfo);
  Sei.Wnd := FormHandle;
  Sei.fMask := SEE_MASK_NOCLOSEPROCESS;
  Sei.lpVerb := 'runas'; // Windows-UAC-Dialog erzwingen
  Sei.lpFile := PChar(Application.ExeName);
  Sei.lpParameters := PChar(Param + ' "' + Argument + '"');
  Sei.nShow := SW_SHOWNORMAL;

  if ShellExecuteEx(@Sei) then
  begin
    repeat
      // 50ms Warteschritte verhindern einen Deadlock beim WM_FONTCHANGE Broadcast
      WaitResult := WaitForSingleObject(Sei.hProcess, 50);
      Application.ProcessMessages;
    until WaitResult <> WAIT_TIMEOUT;

    GetExitCodeProcess(Sei.hProcess, ExitCodeProcess);
    CloseHandle(Sei.hProcess);
    Result := (ExitCodeProcess = 0);
  end;
end;

// Löst GDI-Sperren einer Datei über die Suchmaske des ersten Wortes auf.
class function TFontEngine.TryReleaseFontFile(const FontName: string): Boolean;
var
  FontsFolder, SuchMaske: string;
  SR: TSearchRec;
  GefundeneDatei, FullFontPath: string;
begin
  Result := False;
  FontsFolder := IncludeTrailingPathDelimiter(FM.SysUtils.GetWindowsFontsPath);

  if Pos(' ', FontName) > 0 then
    SuchMaske := Copy(FontName, 1, Pos(' ', FontName) - 1)
  else
    SuchMaske := FontName;

  if Length(SuchMaske) > 8 then
    SetLength(SuchMaske, 8);

  SuchMaske := FontsFolder + SuchMaske + '*.ttf';
  if FindFirst(SuchMaske, faAnyFile, SR) = 0 then
  begin
    try GefundeneDatei := SR.Name; finally FindClose(SR); end;
  end;

  if GefundeneDatei <> '' then
  begin
    FullFontPath := FontsFolder + GefundeneDatei;
    RemoveFontResourceEx(PChar(FullFontPath), FR_PRIVATE, nil);
    RemoveFontResource(PChar(FullFontPath));
    SendMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
    Result := True;
  end;
end;

// Administrative Installation:
// Kopiert die Datei ins System und setzt den HKLM-Registryeintrag.
class function TFontEngine.SilentInstall(const SourcePath: string): Boolean;
var
  FontsFolder, DestPath, RegName: string;
  Reg: TRegistry;
  StartupInput: TGdiplusStartupInput;
  Token: ULONG_PTR;
begin
  Result := False;
  StartupInput.GdiplusVersion := 1;
  StartupInput.DebugEventCallback := nil;
  StartupInput.SuppressBackgroundThread := False;
  StartupInput.SuppressExternalCodecs := False;
  GdiplusStartup(Token, @StartupInput, nil);
  try
    FontsFolder := FM.SysUtils.GetWindowsFontsPath;
    DestPath := TPath.Combine(FontsFolder, ExtractFileName(SourcePath));
    TFile.Copy(SourcePath, DestPath, True);

    RegName := GetFontFamilyNameGDIP(SourcePath);
    if RegName <> '' then
      RegName := RegName + ' (TrueType)'
    else
      RegName := ChangeFileExt(ExtractFileName(SourcePath), '') + ' (TrueType)';

    Reg := TRegistry.Create(KEY_WRITE);
    try
      Reg.RootKey := HKEY_LOCAL_MACHINE;
      if Reg.OpenKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', False) then
      begin
        Reg.WriteString(RegName, ExtractFileName(SourcePath));
        Result := True;
      end;
    finally
      Reg.Free;
    end;
    if Result then
    begin
      AddFontResource(PChar(DestPath));
      SendMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
    end;
  finally
    GdiplusShutdown(Token);
   end;
end;

// Administrative Deinstallation:
// Entfernt die Datei physisch und bereinigt HKLM und HKCU.
class function TFontEngine.SilentUninstall(const RegistryFontName: string): Boolean;
var
  FontsFolder, FullPath: string;
  Reg: TRegistry;
  AlleSchriften: TStringList;
  I: Integer;
  DateiGeloescht, RegGeloescht: Boolean;
begin
  DateiGeloescht := False;
  RegGeloescht := False;
  try
    FontsFolder := IncludeTrailingPathDelimiter(FM.SysUtils.GetWindowsFontsPath);
    FullPath := FontsFolder + RegistryFontName;

    // 1: Physisches Löschen der unblockierten Datei von der Festplatte
    if FileExists(FullPath) then
    begin
      RemoveFontResource(PChar(FullPath));
      TFile.Delete(FullPath);
      if not FileExists(FullPath) then
        DateiGeloescht := True;
    end;
    Reg := TRegistry.Create(KEY_ALL_ACCESS);
    try

      // 2A:
      // Systemweite Registry-Säuberung (HKEY_LOCAL_MACHINE)
      Reg.RootKey := HKEY_LOCAL_MACHINE;
      if Reg.OpenKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', False) then
      begin
        AlleSchriften := TStringList.Create;
        try
          Reg.GetValueNames(AlleSchriften);
          for I := 0 to AlleSchriften.Count - 1 do
          begin
            if SameText(Reg.ReadString(AlleSchriften[I]), RegistryFontName) then
            begin
              Reg.DeleteValue(AlleSchriften[I]);
              RegGeloescht := True;
            end;
          end;
        finally
          AlleSchriften.Free;
        end;
      end;

      // 2B:
      // Benutzerspezifische Registry-Säuberung (HKEY_CURRENT_USER Win10/11 User-Fonts)
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKey('Software\Microsoft\Windows NT\CurrentVersion\Fonts', False) then
      begin
        AlleSchriften := TStringList.Create;
        try
          Reg.GetValueNames(AlleSchriften);
          for I := 0 to AlleSchriften.Count - 1 do
          begin
            if SameText(Reg.ReadString(AlleSchriften[I]), RegistryFontName) then
            begin
            Reg.DeleteValue(AlleSchriften[I]);
            RegGeloescht := True;
            end;
          end;
        finally
          AlleSchriften.Free;
        end;
      end;
    finally
      Reg.Free;
    end;

    if DateiGeloescht or RegGeloescht then
      SendMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
    Result := DateiGeloescht or RegGeloescht;
  except
      Result := False;
  end;
end;

initialization
var StartupInput: TGdiplusStartupInput;
  // GDI+ - Sitzung für die Anwendungs-GUI starten
  StartupInput.GdiplusVersion := 1;
  StartupInput.DebugEventCallback := nil;
  StartupInput.SuppressBackgroundThread := False;
  StartupInput.SuppressExternalCodecs := False;
  GdiplusStartup(GdiplusToken, @StartupInput, nil);

finalization
  // GDI+ - Ressourcen freigeben
  if GdiplusToken <> 0 then
    GdiplusShutdown(GdiplusToken);

  // StringList-Speicher freigeben
  if FFontList <> nil then
    FFontList.Free;
end.
