# -*- coding: utf-8 -*-
"""准备地图设计器的安装包素材：maps_dir.txt + 新版 iss。

背景：安装版装在 Program Files 里，如果地图库还按「exe 上一级」找，
地图会存进 Program Files，Godot 工程读不到。
所以安装包要在 exe 同目录放一个 maps_dir.txt，写明工程 maps 的真实路径。
"""
import io
import os
import shutil

PROJ = r'C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics'
DIST = os.path.join(PROJ, 'tools', 'dist')
MAPS = os.path.join(PROJ, 'maps')
ISS = os.path.join(DIST, '地图设计器.iss')
# 打包出来的绿色版 exe 放这儿，iss 直接引用它 —— 不要再往 dist 复制一份。
# 教训：测试安装时如果把安装目录选成 dist，取消安装会回滚，把同名的源文件一起删掉。
EXE_SRC_DIR = os.path.join(PROJ, 'tools', 'map_exe_app', 'dist')
EXE_SRC = os.path.join(EXE_SRC_DIR, '战棋地图设计器.exe')

os.makedirs(DIST, exist_ok=True)

# 1) maps_dir.txt —— 安装包会把它放到 exe 旁边，app.py 读它决定地图库位置
txt = os.path.join(DIST, 'maps_dir.txt')
with io.open(txt, 'w', encoding='utf-8') as f:
    f.write(MAPS + '\n')
print('写好:', txt, '->', MAPS)

# 2) 旧 iss 先备份
if os.path.isfile(ISS):
    shutil.copy2(ISS, ISS + '.bak')
    print('旧 iss 已备份为 地图设计器.iss.bak')

# 3) 新 iss（必须 UTF-8 带 BOM，否则中文按 ANSI 读会乱码）
iss = r'''[Setup]
AppName=战棋地图设计器
AppVersion=1.3
AppPublisher=CBW工作室
DefaultDirName={autopf}\战棋地图设计器
; 强制不显示「选择开始菜单文件夹」页。
; 本工具不建开始菜单项，按说 auto 就该跳过，但实测仍有版本会弹出来 —— 写死 yes 最稳。
DisableProgramGroupPage=yes
OutputDir=%DIST%
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
Source: "%EXEDIR%\战棋地图设计器.exe"; DestDir: "{app}"; Flags: ignoreversion
; 地图库路径配置：告诉程序战棋工程的 maps 在哪
Source: "%DIST%\maps_dir.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; 只留桌面快捷方式 —— 这么个小工具不值得占开始菜单。
; 卸载入口在「设置 → 应用」里（Inno 会自动登记），不用额外放开始菜单。
Name: "{autodesktop}\战棋地图设计器"; Filename: "{app}\战棋地图设计器.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\战棋地图设计器.exe"; Description: "立即运行地图设计器"; Flags: postinstall nowait skipifsilent
'''.replace('%DIST%', DIST).replace('%EXEDIR%', EXE_SRC_DIR)

if not os.path.isfile(EXE_SRC):
    print('!! 源 exe 不存在：', EXE_SRC)
    print('   先打包：cd map_exe_app && pyinstaller --noconfirm --clean 战棋地图设计器.spec')

with io.open(ISS, 'w', encoding='utf-8-sig') as f:
    f.write(iss)
print('写好:', ISS)

# 4) 确认 Inno Setup 编译器在不在
for cand in (r'C:\Users\Caobo\AppData\Local\Programs\Inno Setup 6\ISCC.exe',
             r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
             r'C:\Program Files\Inno Setup 6\ISCC.exe'):
    if os.path.isfile(cand):
        print('ISCC:', cand)
        break
else:
    print('!! 没找到 ISCC.exe')
