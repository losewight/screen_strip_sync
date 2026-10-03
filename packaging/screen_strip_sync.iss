; Screen Strip Sync — Inno Setup (Windows x64)
; 入口 = helper.exe；Flutter 同目录；卸载清开机自启 Run 项。
; 配置 / 日志在 %LocalAppData%\Screen Strip Sync\，安装目录可写保护路径。
; Flutter 仅支持 x64，本安装包 ArchitecturesAllowed=x64compatible。

#define MyAppName "Screen Strip Sync"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Screen Strip Sync"
#define MyAppExeName "helper.exe"
#define MyAppArch "x64"
; 相对本 .iss 的 staging 目录（由 pack.ps1 填充）
#define MyStaging "..\dist_stage"

[Setup]
AppId={{A8F3C2E1-9B4D-4F6A-8E21-7C5D0B91A3F2}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf64}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; 为什么：Program Files 等受保护路径需提权；运行期数据已迁到 %LocalAppData%
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
; 仅 64 位 Windows（含 ARM64 上的 x64 仿真）
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist_installer
OutputBaseFilename=ScreenStripSync-{#MyAppVersion}-windows-{#MyAppArch}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DefaultDialogFontName=Microsoft YaHei UI
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; 运行中：确认后走 IPC quit（与托盘退出同路径）；CloseApplications 仅作文件占用兜底，不 force
CloseApplications=yes
CloseApplicationsFilter=helper.exe,screen_strip_sync.exe
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyStaging}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\helper.log"
Type: files; Name: "{app}\screen_strip_sync_config.json"
Type: files; Name: "{app}\zeeray_crash.log"
Type: filesandordirs; Name: "{app}\data"

[Code]
const
  AppMutexName = 'Global\ScreenStripSyncHelper';
  IpcPort = 9527;

function IsAppRunning: Boolean;
begin
  Result := CheckForMutexes(AppMutexName);
end;

function IsSetupOrUninstallSilent(const ForUninstall: Boolean): Boolean;
begin
  if ForUninstall then
    Result := UninstallSilent
  else
    Result := WizardSilent;
end;

{ 与托盘「退出」相同：向 helper 发 IPC quit，走 helper_shutdown，不强杀 }
function SendIpcQuit: Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
  Script: String;
begin
  ScriptPath := ExpandConstant('{tmp}\sss_ipc_quit.ps1');
  Script :=
    '$ErrorActionPreference = ''Stop''' + #13#10 +
    '$c = New-Object System.Net.Sockets.TcpClient' + #13#10 +
    '$c.Connect(''127.0.0.1'', ' + IntToStr(IpcPort) + ')' + #13#10 +
    '$w = New-Object System.IO.StreamWriter($c.GetStream())' + #13#10 +
    '$w.Write((''quit'' + [char]10))' + #13#10 +
    '$w.Flush()' + #13#10 +
    'Start-Sleep -Milliseconds 200' + #13#10 +
    '$c.Close()' + #13#10;
  if not SaveStringToFile(ScriptPath, Script, False) then
  begin
    Result := False;
    Exit;
  end;
  Result :=
    Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function WaitUntilAppExits(TimeoutMs: Integer): Boolean;
var
  Elapsed: Integer;
begin
  Elapsed := 0;
  while IsAppRunning do
  begin
    if Elapsed >= TimeoutMs then
    begin
      Result := False;
      Exit;
    end;
    Sleep(100);
    Elapsed := Elapsed + 100;
  end;
  Result := True;
end;

{ 确认后 IPC quit；静默模式直接 quit。失败则请用户手动关，绝不 taskkill。 }
function ConfirmAndCloseRunningApp(const ForUninstall: Boolean): Boolean;
var
  Prompt: String;
begin
  Result := True;
  if not IsAppRunning then
    Exit;

  if not IsSetupOrUninstallSilent(ForUninstall) then
  begin
    if ForUninstall then
      Prompt :=
        '卸载程序检测到 Screen Strip Sync 当前正在运行。' + #13#10#13#10 +
        '是否确认结束进程并继续卸载？'
    else
      Prompt :=
        '安装程序检测到 Screen Strip Sync 当前正在运行。' + #13#10#13#10 +
        '是否确认结束进程并继续安装？';

    if MsgBox(Prompt, mbConfirmation, MB_OKCANCEL) <> IDOK then
    begin
      Result := False;
      Exit;
    end;
  end;

  if not SendIpcQuit then
  begin
    if not IsSetupOrUninstallSilent(ForUninstall) then
      MsgBox(
        '无法通知 Screen Strip Sync 退出。请从托盘选择「退出」后重试。',
        mbError, MB_OK);
    Result := False;
    Exit;
  end;

  if not WaitUntilAppExits(15000) then
  begin
    if not IsSetupOrUninstallSilent(ForUninstall) then
      MsgBox(
        'Screen Strip Sync 尚未退出。请从托盘选择「退出」后重试。',
        mbError, MB_OK);
    Result := False;
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := ConfirmAndCloseRunningApp(False);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  NeedsRestart := False;
  Result := '';
  { 向导期间若用户又启动了程序，安装前再确认一次 }
  if not ConfirmAndCloseRunningApp(False) then
    Result := '已取消安装：未结束正在运行的程序。';
end;

function InitializeUninstall(): Boolean;
begin
  Result := ConfirmAndCloseRunningApp(True);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    RegDeleteValue(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Run',
      'Screen Strip Sync');
    RegDeleteValue(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Run',
      'ScreenStripSyncHelper');
  end;
end;
