#!/system/bin/sh
# daemon.sh — ADB 连接管理守护进程
#
# 开机后在后台运行，根据当前模式管理 ADB 无线连接。
#
# 模式说明:
#   on      — 开启模式: 每 50 秒重连所有设备
#   standby — 预备模式: 每 5 分钟重连最近设备
#   off     — 关闭模式: 恢复默认，休眠等待模式变更

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

# 状态更新间隔（秒）
STATUS_INTERVAL=30

# ============================================================
# 初始化
# ============================================================

# 防止重复启动守护进程
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log "守护进程已在运行 (PID $old_pid)，退出"
        exit 0
    fi
fi

# 保存当前进程 PID
echo $$ > "$PID_FILE"
log "守护进程已启动 (PID $$)"

# 确保配置文件存在
cfg_init

# 首次更新模块状态描述
log "正在更新模块状态..."
update_module_status
log "模块状态更新完成"

# ============================================================
# 退出清理
# ============================================================

cleanup() {
    log "守护进程正在关闭"
    rm -f "$PID_FILE"
    # 退出前更新状态为已停止
    update_module_status
    exit 0
}

trap cleanup TERM INT HUP

# ============================================================
# 模式处理函数
# ============================================================

handle_mode_on() {
    local interval=50
    local tick=0

    log "开启模式: 每 ${interval} 秒全量重连"
    apply_adb_config
    update_module_status

    while true; do
        local current_mode
        current_mode=$(cfg_get mode)
        [ "$current_mode" != "on" ] && return

        reconnect_all
        tick=$((tick + interval))

        # 每 STATUS_INTERVAL 秒更新一次模块状态描述
        if [ $tick -ge $STATUS_INTERVAL ]; then
            update_module_status
            tick=0
        fi

        sleep "$interval"
    done
}

handle_mode_standby() {
    local interval=300
    local tick=0

    log "预备模式: 每 ${interval} 秒重连最近设备"
    apply_adb_config
    update_module_status

    while true; do
        local current_mode
        current_mode=$(cfg_get mode)
        [ "$current_mode" != "standby" ] && return

        reconnect_last
        tick=$((tick + interval))

        # 每 STATUS_INTERVAL 秒更新一次模块状态描述
        if [ $tick -ge $STATUS_INTERVAL ]; then
            update_module_status
            tick=0
        fi

        sleep "$interval"
    done
}

handle_mode_off() {
    log "关闭模式: 恢复默认设置"

    # 恢复原始 ADB 属性
    restore_adb_config

    # 重启 adbd 以应用恢复的默认值
    restart_adbd

    # 更新状态为已停止
    update_module_status

    # 休眠直到模式变更
    while true; do
        local current_mode
        current_mode=$(cfg_get mode)
        [ "$current_mode" != "off" ] && return
        sleep 30
    done
}

# ============================================================
# 主循环
# ============================================================

log "守护进程主循环已启动"

while true; do
    mode=$(cfg_get mode)

    case "$mode" in
        on)
            handle_mode_on
            ;;
        standby)
            handle_mode_standby
            ;;
        off|*)
            handle_mode_off
            ;;
    esac

    # 模式切换前短暂延迟
    sleep 2
done
