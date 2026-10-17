program FontManager;

uses
  Vcl.Forms,
  System.SysUtils,
  FM.FontEngine in 'H:\Dokumente\Embarcadero\Meins\FM-Units\FM.FontEngine.pas',
  U_FM_Main in 'U_FM_Main.pas' {Form1};

{$R *.res}

begin
  // --- WEICHENSTELLUNG FÜR DIE 2. INSTANZ ---
  if ParamCount >= 2 then
  begin
    if ParamStr(1) = '--install' then
    begin
      if TFontEngine.SilentInstall(ParamStr(2)) then ExitCode := 0 else ExitCode := 1;
      Halt;
    end;

    if ParamStr(1) = '--uninstall' then
    begin
      if TFontEngine.SilentUninstall(ParamStr(2)) then ExitCode := 0 else ExitCode := 1;
      Halt;
    end;
  end;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
