#!/system/bin/sh
# webui_server.sh — WebUI HTTP 服务器主循环

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

log "========================================="
log "WebUI 服务器启动 (PID $$)"
log "========================================="

cfg_init

PORT=$(cfg_get webui_port)
PORT=${PORT:-7777}
log "监听端口: $PORT"

# 清理残留
log "清理残留 nc 进程..."
pkill -f "nc.*-l.*-p.*${PORT}" 2>/dev/null
sleep 1

# 防止重复启动
if [ -f "$WEBUI_PID_FILE" ]; then
    old_pid=$(cat "$WEBUI_PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log "WebUI 服务器已在运行 (PID $old_pid)，退出"
        exit 0
    fi
    log "发现过期 PID 文件 (PID $old_pid 已死)，覆盖"
fi

echo $$ > "$WEBUI_PID_FILE"

cleanup() {
    log "WebUI 服务器收到退出信号，正在清理..."
    rm -f "$WEBUI_PID_FILE"
    kill $(jobs -p) 2>/dev/null
    log "WebUI 服务器已退出"
    exit 0
}

trap cleanup TERM INT HUP

# 确保 handler 可执行
chmod 755 "${MODDIR}/webui_handler.sh" 2>/dev/null
log "handler 脚本权限已设置"

log "开始监听循环..."
request_count=0

while true; do
    request_count=$((request_count + 1))
    log "等待连接 #$request_count..."
    busybox nc -l -p "$PORT" -e "${MODDIR}/webui_handler.sh" 2>/dev/null
    rc=$?
    if [ $rc -ne 0 ]; then
        log "!!! nc 退出码: $rc (可能连接中断)"
    fi
    sleep 0.1
done
