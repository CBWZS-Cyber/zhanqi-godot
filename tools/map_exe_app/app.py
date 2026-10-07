# -*- coding: utf-8 -*-
"""战棋 · 地图设计器（EXE 版）
本地 Flask 服务：打开浏览器加载 map-editor.html，
「存入地图库」通过 /api/save 直接写工程 godot-chess-tactics/maps\。
"""
import os
import sys
import json
import threading
import webbrowser

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from flask import Flask, request, jsonify, send_file

# 地图库定位：不写死本机路径（公开仓库安全），自动找 Godot 工程 maps 目录
def _base_dir():
    """程序所在目录（frozen 时是 exe 所在目录）。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def _search_project_maps(base):
    """从 base 逐级往上找战棋工程，认 project.godot 或已存在的 maps 目录。

    为什么需要：安装包要发给别人，包里那份 maps_dir.txt 写的是作者电脑上的路径，
    在对方机器上不存在。这时候得让程序自己去认他的工程。
    """
    cur = os.path.abspath(base)
    for _ in range(5):
        parent = os.path.dirname(cur)
        if not parent or parent == cur:
            break
        cur = parent
        if os.path.isfile(os.path.join(cur, "project.godot")):
            return os.path.join(cur, "maps")
        # 光有个叫 maps 的目录不算数 —— 太容易撞名（测试时就被 Temp\maps 骗过一次）。
        # 里面得真有地图 json 才认。
        m = os.path.join(cur, "maps")
        try:
            if any(f.lower().endswith(".json") for f in os.listdir(m)):
                return m
        except Exception:
            pass
    return None


def _resolve_maps_dir():
    """地图库定位。

    安装版如果还按「exe 上一级」找 maps，地图会存进 Program Files，
    Godot 工程根本读不到。所以多一层配置文件：安装包在 exe 同目录放一个
    maps_dir.txt，写着战棋工程 maps 的真实路径。

    优先级：
      1. 环境变量 ZQ_MAPS_DIR
      2. exe（或脚本）同目录的 maps_dir.txt —— 且上级目录必须真实存在，
         否则说明这份配置是「作者电脑上带过来的」，不能用
      3. 往上自动搜工程（project.godot / 已有 maps）—— 发给别人时靠这条
      4. 绿色版：exe 放在工程 tools/ 下 -> ../maps
      5. exe 同目录/maps（兜底，保证程序还能起来）
    """
    env = os.environ.get("ZQ_MAPS_DIR")
    if env and env.strip():
        return os.path.abspath(env.strip())

    base = _base_dir()

    cfg = os.path.join(base, "maps_dir.txt")
    if os.path.isfile(cfg):
        try:
            with open(cfg, encoding="utf-8-sig") as f:
                p = f.read().strip()
            # 关键：只认「上级目录真实存在」的路径。
            # 别人安装时，包里这份 txt 写的是作者的工程路径；
            # 如果盲信，后面 makedirs 会在他 C 盘凭空造出一整棵目录树。
            if p and os.path.isdir(os.path.dirname(os.path.abspath(p))):
                return os.path.abspath(p)
        except Exception:
            pass

    found = _search_project_maps(base)
    if found:
        return found

    cand = os.path.abspath(os.path.join(base, "..", "maps"))          # 绿色版：工程 maps
    if os.path.isdir(os.path.dirname(cand)):
        return cand
    return os.path.join(base, "maps")

MAPS_DIR = _resolve_maps_dir()
PORT = 8765

def _resource_path(rel):
    if hasattr(sys, "_MEIPASS"):
        return os.path.join(sys._MEIPASS, rel)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), rel)

def _safe_name(name):
    s = "".join(c for c in str(name) if c not in '\\/:*?"<>|').strip()
    return s or "map"

app = Flask(__name__)


@app.route("/")
def index():
    resp = send_file(_resource_path("map-editor.html"))
    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    resp.headers["Pragma"] = "no-cache"
    resp.headers["Expires"] = "0"
    return resp


@app.route("/api/save", methods=["POST"])
def api_save():
    data = request.get_json(silent=True) or {}
    name = _safe_name(data.get("name") or "地图")
    text = data.get("json")
    if text is None:
        return jsonify(ok=False, error="缺少 json 内容")
    try:
        os.makedirs(MAPS_DIR, exist_ok=True)
        path = os.path.join(MAPS_DIR, name + ".json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(str(text))
        return jsonify(ok=True, path=path, dir=MAPS_DIR, files=[name + ".json"])
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500


@app.route("/libpng/<path:filename>")
def lib_png(filename):
    """地图库 PNG 缩略图访问"""
    safe = os.path.basename(str(filename))
    p = os.path.join(MAPS_DIR, safe)
    if os.path.isfile(p):
        resp = send_file(p, mimetype="image/png")
        resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
        return resp
    return ("", 404)


@app.route("/api/maps")
def api_maps():
    items = []
    try:
        os.makedirs(MAPS_DIR, exist_ok=True)
    except Exception:
        pass
    if os.path.isdir(MAPS_DIR):
        for fn in sorted(os.listdir(MAPS_DIR), key=str.lower):
            if fn.lower().endswith(".json"):
                p = os.path.join(MAPS_DIR, fn)
                try:
                    with open(p, encoding="utf-8") as f:
                        txt = f.read()
                    items.append({"name": fn[:-5], "json": txt})
                except Exception:
                    continue
    return jsonify(ok=True, maps=items, dir=MAPS_DIR)


@app.route("/api/set_maps_dir", methods=["POST"])
def api_set_maps_dir():
    """改地图库位置。

    发给别人的安装包里写的是作者电脑上的路径，对方第一次跑很可能指错。
    在界面里改成他自己的 godot-chess-tactics\\maps 就行，会记进 maps_dir.txt，
    下次启动直接生效。
    """
    global MAPS_DIR
    data = request.get_json(silent=True) or {}
    p = str(data.get("dir") or "").strip().strip('"').strip("'")
    if not p:
        return jsonify(ok=False, error="路径为空"), 400
    p = os.path.abspath(p)
    parent = os.path.dirname(p)
    if not os.path.isdir(parent):
        return jsonify(ok=False, error="上级目录不存在：%s" % parent), 400
    try:
        os.makedirs(p, exist_ok=True)
    except Exception as e:
        return jsonify(ok=False, error="无法创建目录：%s" % e), 500
    MAPS_DIR = p
    try:
        with open(os.path.join(_base_dir(), "maps_dir.txt"), "w",
                  encoding="utf-8") as f:
            f.write(p + "\n")
    except Exception:
        pass          # 写不了也无所谓，本次运行照样生效
    return jsonify(ok=True, dir=MAPS_DIR)


@app.route("/api/delete", methods=["POST"])
def api_delete():
    data = request.get_json(silent=True) or {}
    name = str(data.get("name") or "")
    if not name or any(ch in name for ch in '\\/:*?"<>|'):
        return jsonify(ok=False, error="非法文件名"), 400
    path = os.path.join(MAPS_DIR, name + ".json")
    if not os.path.abspath(path).startswith(os.path.abspath(MAPS_DIR)):
        return jsonify(ok=False, error="非法路径"), 400
    try:
        if os.path.exists(path):
            os.remove(path)
            return jsonify(ok=True)
        return jsonify(ok=False, error="文件不存在"), 404
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500


@app.route("/api/shutdown", methods=["POST"])
def api_shutdown():
    threading.Thread(target=_exit_later, daemon=True).start()
    return jsonify(ok=True)


def _exit_later():
    import time
    time.sleep(0.3)
    os._exit(0)


def _single_instance():
    if sys.platform != "win32":
        return True
    import ctypes
    handle = ctypes.windll.kernel32.CreateMutexW(None, False, "Global\\ZQMapEditor_SingleInstance")
    if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        ctypes.windll.kernel32.CloseHandle(handle)
        return False
    return True


if __name__ == "__main__":
    if not _single_instance():
        sys.exit(0)
    threading.Timer(0.8, lambda: webbrowser.open("http://127.0.0.1:%d/" % PORT)).start()
    print("[地图设计器] 服务已启动 http://127.0.0.1:%d/  地图库: %s" % (PORT, MAPS_DIR))
    print("[地图设计器] 关闭浏览器后点程序内“退出程序”，或直接关掉本窗口")
    app.run(host="127.0.0.1", port=PORT, debug=False)
