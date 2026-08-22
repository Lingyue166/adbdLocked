#!/system/bin/sh
# customize.sh — adbdLocked 安装脚本

SKIPUNZIP=0

# ============================================================
# 环境检查
# ============================================================

MIN_API=28

if [ "$API" -lt "$MIN_API" ]; then
    ui_print "! 本模块需要 Android 9+ (API $MIN_API，当前: $API)"
    abort "! 不支持的 Android 版本"
fi

# ============================================================
# Root 方案检测
# ============================================================

if [ -d "/data/adb/ksu" ]; then
    ROOT_SOLUTION="KernelSU"
elif [ -d "/data/adb/sukisu" ]; then
    ROOT_SOLUTION="Sukisu"
elif [ -d "/data/adb/ap" ]; then
    ROOT_SOLUTION="APatch"
elif [ -f "/data/adb/magisk/util_functions.sh" ]; then
    ROOT_SOLUTION="Magisk"
else
    ROOT_SOLUTION="未知"
fi

ui_print "================================"
ui_print "  adbdLocked 安装程序"
ui_print "================================"
ui_print "- Root 方案   : $ROOT_SOLUTION"
ui_print "- 设备架构    : $ARCH"
ui_print "- Android API : $API"
ui_print "================================"

# ============================================================
# 检查 resetprop 是否可用
# ============================================================

if ! command -v resetprop >/dev/null 2>&1; then
    if [ -f "/data/adb/magisk/resetprop" ]; then
        export PATH="/data/adb/magisk:$PATH"
    elif [ -f "/data/adb/ksu/bin/resetprop" ]; then
        export PATH="/data/adb/ksu/bin:$PATH"
    else
        ui_print "! 警告: 未找到 resetprop"
        ui_print "! 部分功能可能无法使用"
    fi
fi

# ============================================================
# 初始化配置目录
# ============================================================

CFG_DIR="/data/adb/adbdLocked"
mkdir -p "$CFG_DIR/logs"

# 如果配置文件不存在则创建默认配置
if [ ! -f "${CFG_DIR}/config.conf" ]; then
    cat > "${CFG_DIR}/config.conf" <<'EOF'
mode=off
bypass_pairing=0
custom_code=
custom_port=
auto_approve=0
last_device=
webui_port=7777
EOF
    ui_print "- 已创建默认配置"
else
    ui_print "- 已保留现有配置"
fi

# ============================================================
# 设置权限
# ============================================================

set_perm_recursive "$MODPATH" 0 0 0755 0644

# 设置脚本可执行权限
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/daemon.sh" 0 0 0755
set_perm "$MODPATH/webui_server.sh" 0 0 0755
set_perm "$MODPATH/webui_handler.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755

# ============================================================
# 安装完成
# ============================================================

ui_print "================================"
ui_print "  安装完成！"
ui_print "================================"
ui_print ""
if [ "$ROOT_SOLUTION" = "KernelSU" ] || [ "$ROOT_SOLUTION" = "Sukisu" ]; then
    ui_print "  WebUI: 点击模块页面的「WebUI」按钮进入"
else
    ui_print "  WebUI: 浏览器访问 http://localhost:7777"
fi
ui_print ""
ui_print "  运行模式:"
ui_print "    开启  - 每 50 秒重连所有设备"
ui_print "    预备  - 每 5 分钟重连最近设备"
ui_print "    关闭  - 恢复默认 ADB 行为"
ui_print ""
ui_print "  模块描述将实时显示运行状态。"
ui_print "  请重启设备以激活模块。"
ui_print "================================"
