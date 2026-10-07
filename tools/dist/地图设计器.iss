[Setup]
AppName=战棋地图设计器
AppVersion=1.3
AppPublisher=CBW工作室
DefaultDirName={autopf}\战棋地图设计器
; 强制不显示「选择开始菜单文件夹」页。
; 本工具不建开始菜单项，按说 auto 就该跳过，但实测仍有版本会弹出来 —— 写死 yes 最稳。
DisableProgramGroupPage=yes
OutputDir=C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics\tools\dist
OutputBaseFilename=地图设计器安装包_1.3
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
; 注意：源 exe 取自打包输出目录（map_exe_app\dist），不是本目录 —— 免得被误删
Source: "C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics\tools\map_exe_app\dist\战棋地图设计器.exe"; DestDir: "{app}"; Flags: ignoreversion
; 地图库路径配置：告诉程序战棋工程的 maps 在哪
Source: "C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics\tools\dist\maps_dir.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; 只留桌面快捷方式 —— 这么个小工具不值得占开始菜单。
; 卸载入口在「设置 → 应用」里（Inno 会自动登记），不用额外放开始菜单。
Name: "{autodesktop}\战棋地图设计器"; Filename: "{app}\战棋地图设计器.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\战棋地图设计器.exe"; Description: "立即运行地图设计器"; Flags: postinstall nowait skipifsilent
