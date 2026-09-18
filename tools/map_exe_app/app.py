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
def _resolve_maps_dir():
    # EXE 通常放在工程 tools/ 下（frozen）；开发时脚本位于 tools/map_exe_app/
    if getattr(sys, "frozen", False):
        base = os.path.dirname(os.path.abspath(sys.executable))       # tools/
        cand = os.path.abspath(os.path.join(base, "..", "maps"))      # 工程 maps
        if os.path.isdir(os.path.dirname(cand)):
            return cand
        return os.path.join(base, "maps")
    here = os.path.dirname(os.path.abspath(__file__))                 # tools/map_exe_app/
    return os.path.abspath(os.path.join(here, "..", "..", "maps"))    # godot-chess-tactics/maps

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
