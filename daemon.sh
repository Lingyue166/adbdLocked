#!/system/bin/sh
# daemon.sh — ADB 连接管理守护进程

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

STATUS_INTERVAL=30

log "========================================="
log "守护进程启动 (PID $$)"
log "========================================="

# 防止重复启动
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log "守护进程已在运行 (PID $old_pid)，退出"
        exit 0
    fi
    log "发现过期 PID 文件 (PID $old_pid 已死)，覆盖"
fi

echo $$ > "$PID_FILE"
log "PID 文件已写入: $$"

cfg_init

log "正在初始化模块状态..."
update_module_status

# 退出清理
cleanup() {
    log "========================================="
    log "守护进程收到退出信号，正在清理..."
    log "========================================="
    rm -f "$PID_FILE"
    update_module_status
    log "守护进程已退出"
    exit 0
}

trap cleanup TERM INT HUP

# 模式处理
handle_mode_on() {
    local interval=50
    local tick=0
    log ">>> 进入开启模式 (每 ${interval}秒 全量重连)"
    apply_adb_config
    update_module_status

    while true; do
        local current_mode
        current_mode=$(cfg_get mode)
        [ "$current_mode" != "on" ] && { log "<<< 模式已变更为 $current_mode，退出开启模式"; return; }

        reconnect_all
        tick=$((tick + interval))

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
    log ">>> 进入预备模式 (每 ${interval}秒 重连最近设备)"
    apply_adb_config
    update_module_status

    while true; do
        local current_mode
        current_mode=$(cfg_get mode)
        [ "$current_mode" != "standby" ] && { log "<<< 模式已变更为 $current_mode，退出预备模式"; return; }

        reconnect_last
        tick=$((tick + interval))

        if [ $tick -ge $STATUS_INTERVAL ]; then
            update_module_status
            tick=0
        fi

        sleep "$interval"
    done
}

handle_mode_off() {
    log ">>> 进入关闭模式"
    restore_adb_config
    restart_adbd
    update_module_status
    log "关闭模式: 等待模式变更..."

    while true; do
        local current_mode
        current_mode=$(cfg_get mode)
        [ "$current_mode" != "off" ] && { log "<<< 模式已变更为 $current_mode，退出关闭模式"; return; }
        sleep 30
    done
}

# 主循环
log "守护进程主循环启动"

while true; do
    mode=$(cfg_get mode)
    log "--- 主循环: 当前模式=$mode ---"

    case "$mode" in
        on)      handle_mode_on ;;
        standby) handle_mode_standby ;;
        off|*)   handle_mode_off ;;
    esac

    log "模式切换中，等待 2秒..."
    sleep 2
done
