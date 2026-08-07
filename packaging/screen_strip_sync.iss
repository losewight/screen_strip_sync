; Screen Strip Sync — Inno Setup (Windows x64)
; 入口 = helper.exe；Flutter 同目录；卸载清开机自启 Run 项。
; 安装到 %LocalAppData%\Programs（可写），因配置/日志写在 helper.exe 旁。
; Flutter 仅支持 x64，本安装包 ArchitecturesAllowed=x64compatible。

#define MyAppName "Screen Strip Sync"
#define MyAppVersion "1.0.0"
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
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; 为什么：exe 旁写 JSON / helper.log，不能装到 Program Files
PrivilegesRequired=lowest
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
CloseApplications=yes
CloseApplicationsFilter=helper.exe,screen_strip_sync.exe
SetupLogging=yes
AppMutex=Local\ScreenStripSyncHelper

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
