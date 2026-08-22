#!/system/bin/sh
# service.sh — 开机完成阶段: 启动守护进程和 WebUI 服务器

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

log "service.sh 已启动"

# 等待开机完成
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

# 额外等待 5 秒，确保系统服务就绪
sleep 5

log "开机完成，正在启动服务"

# 初始化配置
cfg_init

# 终止已存在的进程实例
[ -f "$PID_FILE" ] && { kill "$(cat "$PID_FILE")" 2>/dev/null; rm -f "$PID_FILE"; }
[ -f "$WEBUI_PID_FILE" ] && { kill "$(cat "$WEBUI_PID_FILE")" 2>/dev/null; rm -f "$WEBUI_PID_FILE"; }
pkill -f "daemon.sh" 2>/dev/null
pkill -f "webui_server.sh" 2>/dev/null
pkill -f "nc.*-l.*-p.*7777" 2>/dev/null
rm -f /tmp/adbdLocked_req /tmp/adbdLocked_rsp /tmp/adbdLocked_fifo_* /tmp/adbdLocked_in_* /tmp/adbdLocked_out_*
sleep 2

# 启动 WebUI 服务器
nohup sh "${MODDIR}/webui_server.sh" >> "${LOG_DIR}/webui.log" 2>&1 &
WEBUI_PID=$!
log "WebUI 服务器已启动 (PID $WEBUI_PID)"

# 启动守护进程
nohup sh "${MODDIR}/daemon.sh" >> "${LOG_DIR}/daemon.log" 2>&1 &
DAEMON_PID=$!
log "守护进程已启动 (PID $DAEMON_PID)"

# 验证进程是否存活
sleep 3
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    log "守护进程运行正常"
else
    log "警告: 守护进程启动失败"
fi

if kill -0 "$WEBUI_PID" 2>/dev/null; then
    log "WebUI 服务器运行正常"
else
    log "警告: WebUI 服务器启动失败"
fi

log "service.sh 已完成"
