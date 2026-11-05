; Inno Setup script — builds SaqrPrintAgent-Setup.exe
; Build: iscc installer\SaqrPrintAgent.iss   (expects dist\SaqrPrintAgent.exe from `npm run build`)

#define AppName "Saqr Print Agent"
#define AppVersion "1.2.0"

[Setup]
AppId={{6F1D3B52-8C57-4B0E-9E39-5A1C0E7D2A41}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Saqr POS
DefaultDirName={autopf}\SaqrPrintAgent
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\dist
OutputBaseFilename=SaqrPrintAgent-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayName={#AppName}

[Files]
Source: "..\dist\SaqrPrintAgent.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "run-hidden.vbs";            DestDir: "{app}"; Flags: ignoreversion
Source: "register-task.ps1";         DestDir: "{app}"; Flags: ignoreversion

[INI]
Filename: "{autoprograms}\{#AppName} Status.url"; Section: "InternetShortcut"; Key: "URL"; String: "http://127.0.0.1:{code:GetPort}/"

[Icons]
Name: "{autoprograms}\{#AppName} Log folder"; Filename: "{commonappdata}\SaqrPrintAgent"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\register-task.ps1"" -Action install -InstallDir ""{app}"""; Flags: runhidden; StatusMsg: "Starting the print agent..."
Filename: "http://127.0.0.1:{code:GetPort}/"; Description: "Open the agent status page"; Flags: shellexec postinstall skipifsilent nowait

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\register-task.ps1"" -Action remove"; Flags: runhidden; RunOnceId: "RemoveTask"

[Code]
var
  SettingsPage: TInputQueryWizardPage;

function ConfigPath: String;
begin
  Result := ExpandConstant('{commonappdata}\SaqrPrintAgent\config.json');
end;

function HasConfig: Boolean;
begin
  Result := FileExists(ConfigPath);
end;

// Read "port" from an existing config so the status shortcut matches on upgrades.
function ExistingPort: String;
var
  Json: AnsiString;
  P, Q: Integer;
  Rest: String;
begin
  Result := '9310';
  if LoadStringFromFile(ConfigPath, Json) then
  begin
    P := Pos('"port"', String(Json));
    if P > 0 then
    begin
      Rest := Copy(String(Json), P + 6, 20);
      P := Pos(':', Rest);
      Rest := Trim(Copy(Rest, P + 1, 20));
      Q := 1;
      while (Q <= Length(Rest)) and (Rest[Q] >= '0') and (Rest[Q] <= '9') do Q := Q + 1;
      if Q > 1 then Result := Copy(Rest, 1, Q - 1);
    end;
  end;
end;

function GetPort(Param: String): String;
begin
  if HasConfig then Result := ExistingPort
  else Result := SettingsPage.Values[1];
end;

procedure InitializeWizard;
begin
  SettingsPage := CreateInputQueryPage(wpSelectDir, 'Connect to Saqr',
    'Enter the printing token from Saqr',
    'In Saqr go to Admin -> Settings -> Printing and copy the agent token. Leave the port unchanged unless told otherwise.');
  SettingsPage.Add('Agent token:', False);
  SettingsPage.Add('Port:', False);
  SettingsPage.Values[1] := '9310';
end;

// On upgrades the existing config is kept, so skip the question.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = SettingsPage.ID) and HasConfig;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  PortNum: Integer;
begin
  Result := True;
  if CurPageID = SettingsPage.ID then
  begin
    PortNum := StrToIntDef(Trim(SettingsPage.Values[1]), 0);
    if (PortNum < 1) or (PortNum > 65535) then
    begin
      MsgBox('Please enter a valid port number (default 9310).', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function JsonEscape(S: String): String;
begin
  StringChangeEx(S, '\', '\\', True);
  StringChangeEx(S, '"', '\"', True);
  Result := S;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Json: String;
begin
  if CurStep = ssInstall then
    Exec('taskkill.exe', '/F /IM SaqrPrintAgent.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  if (CurStep = ssPostInstall) and (not HasConfig) then
  begin
    Json := '{' + #13#10 +
            '  "port": ' + Trim(SettingsPage.Values[1]) + ',' + #13#10 +
            '  "token": "' + JsonEscape(Trim(SettingsPage.Values[0])) + '"' + #13#10 +
            '}' + #13#10;
    ForceDirectories(ExtractFileDir(ConfigPath));
    SaveStringToFile(ConfigPath, Json, False);
  end;
end;
