#!/bin/bash
# 平台跳跃游戏发布脚本（版本化防缓存）
# 用法：bash tools/publish.sh
# 流程：导出到 build/web/index_v3.html（版本号随发布升级，如 v4）
#       → index.html 写为跳转页指向最新版本 → 浏览器不会缓存旧版本
# 上线前记得：autoload/game.gd 的 DEBUG_LEVEL_SELECT 改为 false
set -e
cd "$(dirname "$0")/.."

godot --headless --export-release "Web" build/web/index_v3.html

cat > build/web/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>Forest Kingdom Platformer</title>
<script>location.replace("index_v3.html" + location.search);</script>
</head>
<body style="background:#111;color:#fff;text-align:center;padding-top:40vh;font-family:sans-serif">
正在进入游戏… <a href="index_v3.html" style="color:#8f8">点此进入</a>
</body>
</html>
EOF

echo "✓ 发布完成：build/web/（index_v3.html 为游戏页，index.html 为跳转页）"
