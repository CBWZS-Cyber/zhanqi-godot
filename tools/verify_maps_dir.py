# -*- coding: utf-8 -*-
"""模拟「已安装」的 frozen 环境，验证 app.py 认到的地图库路径对不对。

不真的启动程序（那会弹浏览器）：只是把 sys.frozen / sys.executable 伪装成
安装目录里的 exe，然后加载 app.py，看 MAPS_DIR 落在哪。
"""
import importlib.util
import os
import sys

INSTALL_DIR = r'C:\Users\Caobo\AppData\Local\Temp\zqmap_test'
sys.frozen = True
sys.executable = os.path.join(INSTALL_DIR, '战棋地图设计器.exe')

spec = importlib.util.spec_from_file_location(
    'zqapp',
    r'C:\Users\Caobo\WorkBuddy\2026-08-27-18-06-41\godot-chess-tactics\tools\map_exe_app\app.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

print('安装目录        :', INSTALL_DIR)
print('认到的地图库    :', m.MAPS_DIR)
print('地图库存在吗    :', os.path.isdir(m.MAPS_DIR))
if os.path.isdir(m.MAPS_DIR):
    files = [f for f in os.listdir(m.MAPS_DIR) if f.lower().endswith('.json')]
    print('里面的地图      :', files or '(空)')
print('端口            :', m.PORT)
