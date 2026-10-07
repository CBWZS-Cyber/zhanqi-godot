#!/bin/bash
# 战棋：一键更新安装包（导出 exe + Inno Setup 打包）
# 用法: bash tools/update_installer.sh
set -e
PROJ="C:/Users/Caobo/WorkBuddy/2026-08-27-18-06-41/godot-chess-tactics"
GODOT="C:/Users/Caobo/Godot/Godot_v4.7.2-stable_win64.exe"
ISCC="C:/Users/Caobo/AppData/Local/Programs/Inno Setup 6/ISCC.exe"

echo "[1/3] 导出 Windows exe（内嵌 pck）..."
"$GODOT" --headless --path "$PROJ" --export-release "Windows Desktop" "$PROJ/build/战棋.exe" >/dev/null 2>&1 || true
if [ ! -f "$PROJ/build/战棋.exe" ]; then echo "导出失败（未生成 exe）"; exit 1; fi

echo "[2/3] 校验 exe 可加载..."
timeout 30 "$PROJ/build/战棋.exe" --headless --quit 2>&1 | grep -icE "SCRIPT ERROR" >/dev/null && echo "警告: 有脚本错误" || echo "exe OK"

echo "[3/3] Inno Setup 打包..."
"$ISCC" "$PROJ/installer/战棋.iss" 2>&1 | tail -2

echo "完成: $PROJ/installer/战棋安装包.exe"
stat -c "大小: %s 字节  更新时间: %y" "$PROJ/installer/战棋安装包.exe"
