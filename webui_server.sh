#!/system/bin/sh
# webui_server.sh — WebUI HTTP 服务器

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
pkill -f "nc.*-l.*-p.*${PORT}" 2>/dev/null
sleep 1

# 防止重复启动
if [ -f "$WEBUI_PID_FILE" ]; then
    old_pid=$(cat "$WEBUI_PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log "WebUI 服务器已在运行 (PID $old_pid)，退出"
        exit 0
    fi
fi

echo $$ > "$WEBUI_PID_FILE"

cleanup() {
    log "WebUI 服务器正在关闭"
    rm -f "$WEBUI_PID_FILE"
    kill $(jobs -p) 2>/dev/null
    exit 0
}

trap cleanup TERM INT HUP

chmod 755 "${MODDIR}/webui_handler.sh" 2>/dev/null

log "开始监听循环..."

while true; do
    busybox nc -l -p "$PORT" -e "${MODDIR}/webui_handler.sh" 2>/dev/null
    rc=$?
    [ $rc -ne 0 ] && log "nc 退出码: $rc"
    sleep 0.1
done
