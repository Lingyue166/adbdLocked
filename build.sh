#!/bin/bash
# build.sh — adbdLocked 构建脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODULE_PROP="module.prop"

if [ ! -f "$MODULE_PROP" ]; then
    echo "错误: 未找到 $MODULE_PROP"
    exit 1
fi

MOD_ID=$(grep '^id=' "$MODULE_PROP" | cut -d'=' -f2)
MOD_VER=$(grep '^version=' "$MODULE_PROP" | cut -d'=' -f2)

OUTPUT="${1:-${MOD_ID}-${MOD_VER}}"
[[ "$OUTPUT" != *.zip ]] && OUTPUT="${OUTPUT}.zip"

echo "================================"
echo "  adbdLocked 构建工具"
echo "================================"
echo "  模块 ID  : $MOD_ID"
echo "  版本     : $MOD_VER"
echo "  输出文件 : $OUTPUT"
echo "================================"

# 检查必需文件
for f in module.prop META-INF/com/google/android/update-binary META-INF/com/google/android/updater-script; do
    if [ ! -f "$f" ]; then
        echo "错误: 缺少必需文件: $f"
        exit 1
    fi
done

# 清理
rm -f "$OUTPUT"
find . -name ".DS_Store" -name "Thumbs.db" -name "*.swp" -name "*~" -delete 2>/dev/null

# 构建
echo "- 正在构建模块..."

zip -r9 "$OUTPUT" \
    module.prop \
    customize.sh \
    post-fs-data.sh \
    service.sh \
    uninstall.sh \
    common.sh \
    daemon.sh \
    webui_server.sh \
    webui_handler.sh \
    test.sh \
    webui/ \
    webroot/ \
    META-INF/ \
    -x "*.gitkeep" \
    -x "*placeholder" \
    2>/dev/null

# 验证
if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo "================================"
    echo "  构建成功！"
    echo "  输出文件: $OUTPUT ($SIZE)"
    echo "================================"
    echo ""
    echo "  文件列表:"
    unzip -l "$OUTPUT" | tail -n +4 | head -n -2
    echo ""
    echo "  通过 Magisk/KernelSU/Sukisu 刷入此 zip 文件。"
else
    echo "错误: 构建失败"
    exit 1
fi
