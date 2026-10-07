# -*- coding: utf-8 -*-
"""验证四种场景下地图库会落到哪。

  A) 你自己        ：安装目录里的 maps_dir.txt 指向真实工程 -> 用工程 maps
  B) 发给别人      ：txt 里是作者的路径（对方机器上没有）-> 必须忽略，不能照抄
  C) 对方手填路径  ：界面里改过 -> 采纳他填的
  D) 对方有工程    ：没配置，但上级目录有 project.godot -> 自动认出来
"""
import importlib.util
import os
import shutil
import sys

APP = r'C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics\tools\map_exe_app\app.py'
INSTALL = r'C:\Users\Caobo\AppData\Local\Programs\战棋地图设计器'
LAB = r'C:\Users\Caobo\AppData\Local\Temp\zqmap_lab'
N = [0]


def load(frozen_exe):
    sys.frozen = True
    sys.executable = frozen_exe
    N[0] += 1
    spec = importlib.util.spec_from_file_location('zqapp_%d' % N[0], APP)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def setup_app_dir(path, txt_content=None):
    """造一个「某个人的安装目录」：exe 占位 + 可选 maps_dir.txt。"""
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path, exist_ok=True)
    open(os.path.join(path, '战棋地图设计器.exe'), 'wb').close()
    if txt_content is not None:
        with open(os.path.join(path, 'maps_dir.txt'), 'w', encoding='utf-8') as f:
            f.write(txt_content + '\n')


print('=== A：你自己（指向真实工程）===')
m = load(os.path.join(INSTALL, '战棋地图设计器.exe'))
okA = m.MAPS_DIR.endswith(r'godot-chess-tactics\maps') and os.path.isdir(m.MAPS_DIR)
print('  地图库 ->', m.MAPS_DIR, '✅' if okA else '❌')

print()
print('=== B：发给别人（txt 是作者的路径，他机器上没有）===')
d = os.path.join(LAB, 'B')
# 这台机器上 C:\Users\Caobo\... 是真实存在的，没法冒充「别人的电脑」，
# 所以用一个绝对不存在的盘符来代表对方机器上的作者路径。
setup_app_dir(d, r'Z:\作者电脑上才有的路径\godot-chess-tactics\maps')
m = load(os.path.join(d, '战棋地图设计器.exe'))
漏 = m.MAPS_DIR.lower().startswith('z:')
print('  地图库 ->', m.MAPS_DIR)
print('  有没有照抄那份不存在的路径？', '❌ 照抄了' if 漏 else '✅ 没照抄')
print('  上级目录真实存在吗？', '✅' if os.path.isdir(os.path.dirname(m.MAPS_DIR)) else '❌ 会凭空造树')

print()
print('=== C：对方在界面里手填了路径 ===')
d = os.path.join(LAB, 'C')
target = os.path.join(LAB, 'C工程', 'maps')
os.makedirs(os.path.dirname(target), exist_ok=True)     # 父目录真实存在
setup_app_dir(d, target)
m = load(os.path.join(d, '战棋地图设计器.exe'))
okC = m.MAPS_DIR.lower() == target.lower()
print('  地图库 ->', m.MAPS_DIR, '✅ 采纳了' if okC else '❌ 没采纳')

print()
print('=== D：没配置，但上级有战棋工程 ===')
d = os.path.join(LAB, 'D', 'tools', '战棋地图设计器')
setup_app_dir(d)                                        # 没有 maps_dir.txt
proj = os.path.join(LAB, 'D')
open(os.path.join(proj, 'project.godot'), 'w', encoding='utf-8').write('x')
pm = os.path.join(proj, 'maps')
os.makedirs(pm, exist_ok=True)
open(os.path.join(pm, '测试地图.json'), 'w', encoding='utf-8').write('{}')
m = load(os.path.join(d, '战棋地图设计器.exe'))
okD = m.MAPS_DIR.lower() == pm.lower()
print('  地图库 ->', m.MAPS_DIR, '✅ 自动认出来了' if okD else '❌ 没认出来')

shutil.rmtree(LAB, ignore_errors=True)
print()
print('结论：', '四项全部符合预期 ✅' if (okA and not 漏 and okC and okD) else '有项目不符合预期 ❌')
