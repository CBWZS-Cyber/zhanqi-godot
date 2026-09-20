[Setup]
AppName=战棋
AppVersion=1.0
AppPublisher=CBW工作室
DefaultDirName={autopf}\战棋
DefaultGroupName=战棋
UninstallDisplayName=战棋
OutputDir=C://Users//Caobo//WorkBuddy//2026-08-27-18-06-41//godot-chess-tactics//installer
OutputBaseFilename=战棋安装包
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "C://Users//Caobo//WorkBuddy//2026-08-27-18-06-41//godot-chess-tactics//build//战棋.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\战棋"; Filename: "{app}\战棋.exe"
Name: "{group}\战棋"; Filename: "{app}\战棋.exe"
Name: "{group}\卸载战棋"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\战棋.exe"; Description: "立即运行战棋"; Flags: postinstall nowait skipifsilent
