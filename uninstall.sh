#!/system/bin/sh
# uninstall.sh — 模块卸载清理
#
# 恢复所有 ADB 属性，终止后台进程，清理配置文件。

MODDIR="${0%/*}"

CFG_DIR="/data/adb/adbdLocked"
PID_FILE="${CFG_DIR}/daemon.pid"
WEBUI_PID_FILE="${CFG_DIR}/webui.pid"
ORIG_PROPS_FILE="${CFG_DIR}/orig_props.conf"

# ============================================================
# 终止运行中的进程
# ============================================================

[ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
[ -f "$WEBUI_PID_FILE" ] && kill "$(cat "$WEBUI_PID_FILE")" 2>/dev/null

# 按名称强制终止作为备选方案
pkill -f "daemon.sh" 2>/dev/null
pkill -f "webui_server.sh" 2>/dev/null

# ============================================================
# 恢复原始 ADB 属性
# ============================================================

if [ -f "$ORIG_PROPS_FILE" ]; then
    orig_secure=$(grep "^ro.adb.secure=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)
    orig_port=$(grep "^service.adb.tcp.port=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)
    orig_pport=$(grep "^persist.sys.adb.tcp.port=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)

    [ -n "$orig_secure" ] && resetprop -n ro.adb.secure "$orig_secure"
    [ -n "$orig_port" ] && resetprop -n service.adb.tcp.port "$orig_port"
    [ -n "$orig_pport" ] && resetprop -n persist.sys.adb.tcp.port "$orig_pport"
fi

# 强制恢复安全模式以确保安全
resetprop -n ro.adb.secure 1 2>/dev/null

# ============================================================
# 清理配置目录
# ============================================================

rm -rf "$CFG_DIR"

# ============================================================
# 重启 adbd 以应用干净状态
# ============================================================

stop adbd 2>/dev/null
sleep 1
start adbd 2>/dev/null

echo "adbdLocked: 已卸载，ADB 已恢复默认设置。"
