unit U_FM_Main;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShlObj,
  System.SysUtils, System.Variants, System.Classes, System.UITypes,
  System.Win.Registry, System.IOUtils, System.Generics.Collections,
  Vcl.ClipBrd, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.Menus, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Grids, Vcl.ComCtrls,
  FM.FontEngine;

const
  WM_AFTER_SHOW = WM_USER + 300; // Message definieren

type
  TForm1 = class(TForm)
    MainMenu1: TMainMenu;
      MM_Datei: TMenuItem;
        MM_Beenden: TMenuItem;      // TAG = 10
      MM_Schrift: TMenuItem;
        MM_Font_Instal: TMenuItem;  // TAG = 20
        MM_FontDeinst: TMenuItem;   // TAG = 21
        N1: TMenuItem;
        MM_WriteReport: TMenuItem;  // TAG = 22
    Panel_01: TPanel;
      Panel02: TPanel;
        CBFontDir: TComboBox;
        Label3: TLabel;
        CbFontFilter: TComboBox;
        Label4: TLabel;
        EdSearch: TEdit;
      Panel_03: TPanel;
        LbFontCount: TLabel;
        LBFonts: TListBox;
      Splitter1: TSplitter;
      Panel_04: TPanel;
        SG: TStringGrid;
      Panel_05: TPanel;
        RgMode: TRadioGroup;
        Label1: TLabel;
        CbFontSize: TComboBox;
        Label2: TLabel;
        CbCols: TComboBox;
        CbShowUnicode: TCheckBox;
    StBar: TStatusBar;
    Timer1: TTimer;

    procedure LBFontsDrawItem(Control: TWinControl; Index: Integer;
                              Rect: TRect; State: TOwnerDrawState);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure LBFontsClick(Sender: TObject);
    procedure SGDrawCell(Sender: TObject; ACol, ARow: LongInt; Rect: TRect;
                         State: TGridDrawState);
    procedure SGDblClick(Sender: TObject);
    procedure SGKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure ChangeFontSizeOrColumns(Sender: TObject);
    procedure ChangeViewMode(Sender: TObject);
    procedure MenuItemClick(Sender: TObject);
    procedure CbFontFilterChange(Sender: TObject);
    procedure EdSearchChange(Sender: TObject);

  private const
    CR = sLineBreak;
  private
    procedure UpdateFontDisplay;
    procedure WMAfterShow(var Msg: TMessage); message WM_AFTER_SHOW;
    procedure ShowFontTable(const AFontName: string;
                            AColCount, AFontSize: Integer;
                            AStartChar, AEndChar: Integer;
                            Mode: Integer);
    procedure SetStBar;
  end;

var
  Form1: TForm1;

implementation
Uses FM.SysUtils;
{$R *.dfm}

// Zeichnet Items
procedure TForm1.LBFontsDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  FontName: string;
begin
  if Index < 0 then Exit;
  FontName := LBFonts.Items[Index];

  with LBFonts.Canvas do
  begin
    // 1: HINTERGRUND DIREKT ZEICHNEN (Zelle vorbereiten)
    if odSelected in State then
    begin
      Brush.Color := clHighlight;
      Font.Color := clHighlightText;
    end
    else
    begin
      Brush.Color := LBFonts.Color;
      Font.Color := LBFonts.Font.Color; // Standardmäßig schwarz
    end;

    // Hintergrund ausmalen
    FillRect(Rect);

    // 2: SYSTEM-SCHUTZSCHILD PRÜFEN (Stile anpassen)
    if not (odSelected in State) and TFontEngine.IsSystemProtectedFont(FontName) then
    begin
      Font.Color := clGrayText;
      Font.Style := [fsItalic];
    end
    else if not (odSelected in State) then
    begin
      Font.Style := [];
    end;

    // 3: TEXT SCHREIBEN
    // Berechnet den y-Startpunkt, damit der Text bei 24px Höhe exakt mittig sitzt
    var TextY := Rect.Top + ((Rect.Height - TextHeight(FontName)) div 2);

    // Text mit dem neuen, zentrierten Y-Wert ausgeben
    TextOut(Rect.Left + 4, TextY, FontName);

    // 4: FOKUSRAHMEN (Tastatur-Bedienung)
    if odFocused in State then
      DrawFocusRect(Rect);
  end;
end;

// Menu-Items
procedure TForm1.MenuItemClick(Sender: TObject);
var Tag: Byte;
    OpenDlg: TOpenDialog;
    SelectedFontName, InstalledName: string;
begin
  Tag:= (Sender as TMenuItem).Tag;
  Case Tag of
    10: Close;  // Beenden

    20: begin   // Font Installieren
      OpenDlg := TOpenDialog.Create(Self);
      try
        OpenDlg.Filter := 'Schriftarten (*.ttf; *.otf)|*.ttf;*.otf|TrueType-Schriftarten'
                          +' (*.ttf)|*.ttf|OpenType-Schriftarten (*.otf)|*.otf';
        OpenDlg.Title := 'Schriftart für die Installation auswählen';

        if OpenDlg.Execute then
        begin
          // Aufruf der Engine (übergibt das Handle für das UAC-Windows-Fenster)
          if TFontEngine.InstallFontFamily(Self.Handle, OpenDlg.FileName, InstalledName) then
          begin
            UpdateFontDisplay; // Liste im UI frisch einlesen
            var TargetIndex:= LBFonts.Items.IndexOf(InstalledName);
            if TargetIndex <> -1 then
            begin
              // 2. Element selektieren
              LBFonts.ItemIndex := TargetIndex;
              // 3: Sichtbare Zeilen berechnen
              var VisibleItems := LBFonts.ClientHeight div LBFonts.ItemHeight;
              // TopIndex ist die oberste Zeile. Damit TargetIndex in der Mitte landet
              var TopIndex := TargetIndex - (VisibleItems div 2);
              // Absicherung: TopIndex darf nicht negativ werden
              if TopIndex < 0 then
                TopIndex := 0;
              // 4: Per Windows-API den berechneten TopIndex erzwingen
              SendMessage(LBFonts.Handle, LB_SETTOPINDEX, TopIndex, 0);
              // Font-Inhalt anzeigen
              LBFontsClick(Self);
            end;

            StBar.Panels[1].Text := 'Schriftart erfolgreich installiert: ' +InstalledName;
          end
          else
          if InstalledName = 'ALREADY_INSTALLED' then
          begin
            StBar.Panels[1].Text := 'Installation abgebrochen: ' +
                                    'Schriftart existiert bereits.';
          end;
          Timer1.Enabled := True;
        end;
      finally
        OpenDlg.Free;
      end;
    end;

    21: begin   // Font Deinstallieren
      if LBFonts.ItemIndex < 0 then
      begin
        StBar.Panels[1].Text := 'Bitte wählen Sie zuerst eine Schriftart aus der Liste.';
        Timer1.Enabled := True;
        Exit;
      end;

      // Den aktuell selektierten Namen aus der ListBox holen
      SelectedFontName := LBFonts.Items[LBFonts.ItemIndex];

      // Vorab-Check im Hauptprogramm für sauberes UI-Feedback
      if TFontEngine.IsSystemProtectedFont(SelectedFontName) then
      begin
        MessageDlg('⚠️ SYSTEMSCHUTZ:' + CR + CR +
                   'Die Schriftart "' + SelectedFontName +
                   '" ist eine essenzielle Windows-Systemschriftart.' + CR +
                   'Die Deinstallation wurde aus Sicherheitsgründen blockiert.',
                   mtError, [mbOK], 0);
        StBar.Panels[1].Text := 'Aktion blockiert: System-Schriftart geschützt!';
        Timer1.Enabled := True;
        Exit;
      end;


      if MessageDlg('Möchten Sie die Schriftart "' + SelectedFontName +
                    '" wirklich dauerhaft deinstallieren?',
                    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        // Aufruf der Engine-Deinstallation (löst GDI-Sperren und säubert Registry-Kreuz)
        if TFontEngine.UninstallFontFamily(Self.Handle, SelectedFontName) then
        begin
          // 1: Liste im UI frisch einlesen
          UpdateFontDisplay;

          // 2: Selektion explizit auf "nichts ausgewählt" setzen
          LBFonts.ItemIndex := -1;

          // 3: StringGrid Leeren
          SendMessage(SG.Handle, WM_SETREDRAW, 0, 0);
          try
            for var row := 0 to SG.RowCount - 1 do
              for var col := 0 to SG.ColCount - 1 do
              begin
                SG.Cells[col, row] := '';
                SG.Objects[col, row] := nil;
              end;

            // StringGrid auf eine leere Matrix stzen
            SG.ColCount := 1;
            SG.RowCount := 1;
          finally
            SendMessage(SG.Handle, WM_SETREDRAW, 1, 0);
            SG.Invalidate; // Neuzeichnen erzwingen
          end;

          StBar.Panels[1].Text := 'Schriftart erfolgreich deinstalliert.';
        end
        else
        begin
          StBar.Panels[1].Text := 'Fehler bei der Deinstallation.';
        end;
        Timer1.Enabled := True;
      end;
    end;

    22: begin // Report erstellen
      begin
        var SL := TStringList.Create;
        try
          var FL := TFontEngine.GetFonts; // Schreibgeschützte Referenz holen

          SL.Add(Format('%-60s | %-30s', ['GDI-Name (Abgeschnitten)', 'Echter System-Name']));
          SL.Add(StringOfChar('-', 95));

          for var i := 0 to FL.Count - 1 do
          begin
            // Nutzt Engine, um den echten Namen aufzulösen
            var FullFontName := TFontEngine.GetFullFontNameFromSystem(FL[I]);
            SL.Add(Format('%-60s | %-30s', [FL[I], FullFontName]));
          end;

          SL.SaveToFile('Report.txt');
          StBar.Panels[1].Text := 'Report.txt erfolgreich generiert.';
          Timer1.Enabled := True;
        finally
          SL.Free;
        end;
      end;
    end;

  End;  // Case
end;

/// <summary>
/// Synchronisiert die Anzeige mit den Daten aus der Engine.
/// </summary>
procedure TForm1.UpdateFontDisplay;
var
  I, MaxWidth, ItemWidth: Integer;
  Filter: TFontFilterType;
  SearchQuery: string;
begin
  // Den gewählten Filter-Typ aus der ComboBox ermitteln (0=Alle, 1=Monospace, 2=Bitmap)
  case CbFontFilter.ItemIndex of
    1: Filter := ftMonospace;
    2: Filter := ftBitmap;
    else Filter := ftAll;
  end;

  // Suchbegriff aus dem Edit-Feld holen
  SearchQuery := EdSearch.Text;

  LBFonts.Items.BeginUpdate;
  try
    // Aufruf der Engine mit Live-Filterung
    TFontEngine.GetFontsFiltered(LBFonts.Items, SearchQuery, Filter);
  finally
    LBFonts.Items.EndUpdate;
  end;

  // Horizontale Scrollbar für die gefilterte Liste neu berechnen
  MaxWidth := 0;
  LBFonts.Canvas.Font.Assign(LBFonts.Font);

  for I := 0 to LBFonts.Items.Count - 1 do
  begin
    ItemWidth := LBFonts.Canvas.TextWidth(LBFonts.Items[I]);
    if ItemWidth > MaxWidth then
      MaxWidth := ItemWidth;
  end;
  LBFonts.ScrollWidth := MaxWidth + 20;

  LbFontCount.Caption := LBFonts.Items.Count.ToString + ' Fonts gefunden...';
end;

// Gibt den Font-Path zurück
function GetWindowsFontsPath: string;
var
  Path: array[0..MAX_PATH] of Char;
begin
  // Ermittelt den Pfad über die Windows-API
  if SUCCEEDED(SHGetFolderPath(0, CSIDL_FONTS, 0, 0, Path)) then
    Result := IncludeTrailingPathDelimiter(Path)
  else
    Result := 'C:\Windows\Fonts\'; // Fallback
end;

// Gibt den Dateinamen (z. B. arial.ttf) passend zum gesuchten Font-Namen zurück
function GetFontFileName(const AFontName: string): string;
var
  Reg: TRegistry;
  ValueNames: TStringList;
  ValName: string;
begin
  Result := '';
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') then
    begin
      ValueNames := TStringList.Create;
      try
        Reg.GetValueNames(ValueNames);
        for ValName in ValueNames do
        begin
          // Der Registry-Schlüssel enthält oft Zusätze wie "(TrueType)"
          if Pos(UpperCase(AFontName), UpperCase(ValName)) > 0 then
          begin
            Result := Reg.ReadString(ValName);
            Break;
          end;
        end;
      finally
        ValueNames.Free;
      end;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

// StBar-Text löschen
procedure TForm1.Timer1Timer(Sender: TObject);
begin
  if StBar.Panels[0].Text <> '' then StBar.Panels[0].Text:= '';
  if StBar.Panels[1].Text <> '' then StBar.Panels[1].Text:= '';
  Timer1.Enabled:= False;
end;


procedure TForm1.SGDblClick(Sender: TObject);
var
  CellText: string;
begin
  if (SG.Col >= 0) and (SG.Row >= 0) then
  begin
    CellText := SG.Cells[SG.Col, SG.Row];
    if CellText <> '' then
    begin
      Clipboard.AsText := CellText;
      // Kurzes visuelles Feedback (z.B. in der Statusleiste oder Caption)
      StBar.Panels[1].Text := 'Zeichen in die Zwischenablage kopiert: ';
      Timer1.Enabled:= True;
    end;
  end;
end;

// Enter -> Sel.-Zeichen in die Zwischenablage Kopieren
procedure TForm1.SGKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  CellText: string;
begin
  if Key = VK_RETURN then
  begin
    if (SG.Col >= 0) and (SG.Row >= 0) then
    begin
      CellText := SG.Cells[SG.Col, SG.Row];
      if CellText <> '' then
      begin
        Clipboard.AsText := CellText;
        Key := 0; // Verhindert Beep
        StBar.Panels[1].Text:= 'Zeichen in die Zwischenablage kopiert: ';
        Timer1.Enabled:= True;
      end;
    end;
  end;
end;

// SG-Zelle zeichnen
procedure TForm1.SGDrawCell(Sender: TObject; ACol, ARow: LongInt;
                            Rect: TRect; State: TGridDrawState);
var
  CellText, HexStr: string;
  UnicodeVal: NativeInt;
  SymbolRect: TRect;
begin
  CellText := SG.Cells[ACol, ARow];
  if CellText = '' then Exit;

  // Hintergrund zeichnen (inkl. Selektionsfarbe)
  if gdSelected in State then
    SG.Canvas.Brush.Color := clInfoBk
  else
    SG.Canvas.Brush.Color := clWindow;

  SG.Canvas.FillRect(Rect);

  // Wenn "Unicodes anzeigen" aktiv ist:
  if CbShowUnicode.Checked then
  begin
    // 1: KLEINEN HEX-CODE OBEN LINKS ZEICHNEN
    SG.Canvas.Font.Name := 'Segoe UI';
    SG.Canvas.Font.Size := 8;
    SG.Canvas.Font.Style := [];
    SG.Canvas.Font.Color := clGray;

    if Assigned(SG.Objects[ACol, ARow]) then
    begin
      UnicodeVal := NativeInt(SG.Objects[ACol, ARow]);
      HexStr := '$' + IntToHex(UnicodeVal, 4);
      SG.Canvas.TextOut(Rect.Left + 4, Rect.Top + 4, HexStr);
    end;

    // 2: SYMBOL IM UNTEREN BEREICH DER ZELLE ZENTRIEREN
    SymbolRect := Rect;
    SymbolRect.Top := Rect.Top + 24;  // Puffer für den Hex-Code oben freihalten!

    SG.Canvas.Font.Name := SG.Font.Name;
    SG.Canvas.Font.Size := CbFontSize.Items[CbFontSize.ItemIndex].ToInteger;
    SG.Canvas.Font.Color := clWindowText;

    DrawTextW(SG.Canvas.Handle, PWideChar(CellText), Length(CellText),
              SymbolRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end
  else
  begin
    // Standard-Ansicht ohne Hex-Code (volle Zelle nutzen)
    SG.Canvas.Font.Name := SG.Font.Name;
    SG.Canvas.Font.Size := CbFontSize.Items[CbFontSize.ItemIndex].ToInteger;
    SG.Canvas.Font.Color := clWindowText;

    DrawTextW(SG.Canvas.Handle, PWideChar(CellText), Length(CellText),
              Rect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end;
end;

// StringGrid zeichnen
procedure TForm1.ShowFontTable(const AFontName: string;
                               AColCount, AFontSize: Integer;
                               AStartChar, AEndChar: Integer;
                               Mode: Integer);
var
  i, validIndex, row, col: Integer;
  BaseSize, ColWidth, RowSize: Integer;
  Ch: WideChar;
  ValidChars: TList<Integer>;
//----------------------------------------------------------------------------------------
  function GlyphExists(AChar: WideChar): Boolean;
  var
    Bmp: TBitmap;
    GlyphIndex: Word;
  begin
    GlyphIndex := 0;
    Bmp := TBitmap.Create;
    try
      Bmp.Width := 1;
      Bmp.Height := 1;
      Bmp.Canvas.Font.Assign(SG.Font); // Zugewiesenen AFontName
      Winapi.Windows.GetGlyphIndicesW(Bmp.Canvas.Handle, @AChar, 1,
                                      @GlyphIndex, GGI_MARK_NONEXISTING_GLYPHS);
      Result := (GlyphIndex <> 0) and (GlyphIndex <> $FFFF);
    finally
      Bmp.Free;
    end;
  end;
//----------------------------------------------------------------------------------------
begin
  if AColCount <= 0 then Exit;

  SG.FixedCols := 0;
  SG.FixedRows := 0;
  // Dem StringGrid den unbeschnittenen, echten Namen mitgeben
  SG.Font.Name := AFontName;
  SG.Font.Size := AFontSize;
  SG.HandleNeeded;

  ValidChars := TList<Integer>.Create;
  try
    for i := AStartChar to AEndChar do
    begin
      if (Mode <> 0) and (i >= 128) and (i <= 159) then Continue;
      Ch := WideChar(i);
      if GlyphExists(Ch) then ValidChars.Add(i);
    end;

    if ValidChars.Count = 0 then Exit;

    SG.ColCount := AColCount;
    SG.RowCount := (ValidChars.Count + AColCount - 1) div AColCount;

    // Speicherbereinigung alter Zellinhalte erzwingen
    for row := 0 to SG.RowCount - 1 do
      for col := 0 to SG.ColCount - 1 do
      begin
        SG.Cells[col, row] := '';
        SG.Objects[col, row] := nil;
      end;

    BaseSize := SG.Canvas.TextHeight('Wg') + 24;
    if BaseSize < (AFontSize * 2) then BaseSize := Round(AFontSize * 2.2);
    ColWidth := BaseSize;
    RowSize := BaseSize;

    if CbShowUnicode.Checked then
    begin
      SG.Canvas.Font.Name := 'Segoe UI'; SG.Canvas.Font.Size := 8;
      var MinColWidth := SG.Canvas.TextWidth('$0000') + 16;
      if ColWidth < MinColWidth then ColWidth := MinColWidth;
      RowSize := BaseSize + 20;
    end;

    SG.DefaultColWidth := ColWidth;
    SG.DefaultRowHeight := RowSize;

    SendMessage(SG.Handle, WM_SETREDRAW, 0, 0);
    try
      for validIndex := 0 to ValidChars.Count - 1 do
      begin
        col := validIndex mod AColCount;
        row := validIndex div AColCount;
        if (col < SG.ColCount) and (row < SG.RowCount) then
        begin
          SG.Cells[col, row] := String(WideChar(ValidChars[validIndex]));
          SG.Objects[col, row] := TObject(NativeInt(ValidChars[validIndex]));
        end;
      end;
    finally
      SendMessage(SG.Handle, WM_SETREDRAW, 1, 0);
      SG.Invalidate;
    end;
  finally
    ValidChars.Free;
  end;
end;


procedure TForm1.LBFontsClick(Sender: TObject);
var
  StartChar, EndChar, Mode: Integer;
  TruncatedName, FullFontName: string;
begin
  if LBFonts.ItemIndex < 0 then Exit;

  // 1: Hole den (evtl. von Windows/VCL abgeschnittenen) Namen aus der Liste
  TruncatedName := LBFonts.Items[LBFonts.ItemIndex];

  // 2: Hole den unbegrenzten Namen über die DirectWrite/GDI-Hintertür
  FullFontName := TFontEngine.GetFullFontNameFromSystem(TruncatedName);

  Mode := RgMode.ItemIndex; // 0 = ASCII, 1 = Alle

  case Mode of
    0: begin StartChar := 0; EndChar := 255; end;
    1: begin StartChar := $0020; EndChar := $FFFF; end;
    else
    begin
      StartChar := 0; EndChar := 255;
    end;
  end;

  // Übergabe des echten Namens an die Matrix-Generierung
  ShowFontTable(FullFontName,
                CbCols.Items[CbCols.ItemIndex].ToInteger,
                CbFontSize.Items[CbFontSize.ItemIndex].ToInteger,
                StartChar, EndChar, Mode);
  SG.Col:= 0;
  SG.Row:= 0;
end;

// OnChange-Ereignis der ComboBox (Anzeigen: Alle Schriftfamilien...)
procedure TForm1.CbFontFilterChange(Sender: TObject);
begin
  UpdateFontDisplay;
  // Nach dem Filtern die erste Schriftart in die Matrix laden, falls vorhanden
  if LBFonts.Items.Count > 0 then
  begin
    LBFonts.ItemIndex := 0;
    LBFontsClick(Self);
  end;
end;

// StBar einstellen
procedure TForm1.SetStBar;
begin
  StBar.Panels[2].Width:= 200;  // Fixe breite
  StBar.Panels[1].Width:= MulDiv(StBar.Width - 200, 50, 100); // 50%
  StBar.Panels[0].Width:= MulDiv(StBar.Width - 200, 50, 100); // 50%
end;

// FontSize oder Spaltenanzahl wurden geändert
procedure TForm1.ChangeFontSizeOrColumns(Sender: TObject);
begin
  if (LBFonts.Items.Count = 0) or (LBFonts.ItemIndex = -1) then Exit
  else
    LBFontsClick(Self);            // Inhalt des Fonts anzeigen
end;

// ASCII-Zeichen oder Glyphen wurde geändert
procedure TForm1.ChangeViewMode(Sender: TObject);
begin
  if (LBFonts.Items.Count = 0) or (LBFonts.ItemIndex = -1) then Exit
  else
    LBFontsClick(Self);            // Inhalt des Fonts anzeigen
end;

// Das OnChange-Ereignis deines Suche-Eingabefeldes
procedure TForm1.EdSearchChange(Sender: TObject);
begin
  UpdateFontDisplay;
  if LBFonts.Items.Count > 0 then
  begin
    LBFonts.ItemIndex := 0;
    LBFontsClick(Self);
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  ReportMemoryLeaksOnShutdown:= True;
end;

procedure TForm1.WMAfterShow(var Msg: TMessage);
begin
  CBFontDir.Clear;
  SetStBar;

  // 1: Liste initial über die Engine befüllen & skalieren
  UpdateFontDisplay;

  // 2: Ordner-Pfad auslesen
  CBFontDir.Items.Add(FM.SysUtils.GetWindowsFontsPath);
  CBFontDir.ItemIndex := 0;

  // 3: Erste Schriftart automatisch selektieren und Matrix zeichnen
  if LBFonts.Items.Count > 0 then
  begin
    LBFonts.ItemIndex := 0;
    LBFontsClick(Self); // Erste Schriftart direkt in die Matrix laden
  end;

  LbFontCount.Caption:= LBFonts.Items.Count.ToString + ' Fonts gefunden...';
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  PostMessage(Self.Handle, WM_AFTER_SHOW, 0, 0);
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  SetStBar;
end;

end.

