[Setup]
AppName=战棋地图设计器
AppVersion=1.1
AppPublisher=CBW工作室
DefaultDirName={autopf}\战棋地图设计器
DefaultGroupName=战棋工具
OutputDir=C://Users//Caobo//WorkBuddy//2026-08-27-18-06-41//godot-chess-tactics//tools//dist
OutputBaseFilename=地图设计器安装包
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\战棋地图设计器.exe

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: checkedonce

[Files]
Source: "C://Users//Caobo//WorkBuddy//2026-08-27-18-06-41//godot-chess-tactics//tools//dist//战棋地图设计器.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\战棋地图设计器"; Filename: "{app}\战棋地图设计器.exe"; Tasks: desktopicon
Name: "{group}\战棋地图设计器"; Filename: "{app}\战棋地图设计器.exe"
Name: "{group}\卸载战棋地图设计器"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\战棋地图设计器.exe"; Description: "立即运行地图设计器"; Flags: postinstall nowait skipifsilent
