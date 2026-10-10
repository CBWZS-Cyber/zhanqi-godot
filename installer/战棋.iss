[Setup]
AppName=战棋
AppVersion=10.5.4
AppVerName=战棋 10.5.4
AppPublisher=CBW工作室
; 2026-10-04 起装到**用户可写**目录（原来是 {autopf} = C:\Program Files\战棋）。
; 原因：自动更新要往游戏目录写 _update/ 并替换 exe，而 Program Files 下
; 普通用户进程没有写权限 —— 不换目录的话自动更新必然失败。
; ⚠️ PrivilegesRequired 保持 admin 不动：免杀软加固要把 CBW 证书写进 HKLM
; 根证书库（见下面 [Run] 的 certutil -addstore -f Root），那一步必须管理员权限。
; 两者不冲突 —— 提权安装，但文件落到当前用户的 LocalAppData（不需要额外授权即可改）。
DefaultDirName={localappdata}\Programs\战棋
DefaultGroupName=战棋
UninstallDisplayName=战棋 10.5.4
UninstallDisplayIcon={app}\战棋.exe
OutputDir=C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics/installer
OutputBaseFilename=战棋安装包_10.5.4_20261010
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
; 免杀软加固：安装时要把 CBW 证书写进「受信任的根证书颁发机构」(HKLM)，
; 因此必须管理员权限 —— 安装时会弹一次 UAC，这是预期行为。
PrivilegesRequired=admin
VersionInfoVersion=10.5.4.0
VersionInfoCompany=CBW工作室
VersionInfoDescription=战棋 10.5.4 安装程序
VersionInfoProductName=战棋
VersionInfoProductVersion=10.5.4
VersionInfoCopyright=CBW工作室

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics/build/战棋.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics/installer/战棋证书.cer"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\战棋"; Filename: "{app}\战棋.exe"
Name: "{group}\战棋"; Filename: "{app}\战棋.exe"
Name: "{group}\卸载战棋"; Filename: "{uninstallexe}"

[Run]
; 自动导入签名证书到根证书库（runhidden 静默执行）。
; 注意：不要加 skipifsilent —— 静默安装也必须执行，否则"测试全绿其实证书没装"。
Filename: "certutil.exe"; Parameters: "-addstore -f Root ""{app}\战棋证书.cer"""; Flags: runhidden
Filename: "{app}\战棋.exe"; Description: "立即运行战棋"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; 卸载时移除导入的根证书，不留痕迹
; RunOnceId 必填：否则多用户/重复卸载时该条目会被执行多次（编译器也会告警）
Filename: "certutil.exe"; Parameters: "-delstore Root ""CBW"""; Flags: runhidden; RunOnceId: "DelCBWRootCert"
