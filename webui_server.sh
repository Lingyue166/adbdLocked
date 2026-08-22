#!/system/bin/sh
# webui_server.sh — WebUI HTTP 服务器主循环
# 使用 busybox nc -e 调用 webui_handler.sh 处理每个连接

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

cfg_init

PORT=$(cfg_get webui_port)
PORT=${PORT:-7777}

# 清理残留进程和端口
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

log "WebUI 服务器已启动，端口 $PORT (PID $$)"

# 确保 handler 脚本可执行
chmod 755 "${MODDIR}/webui_handler.sh" 2>/dev/null

while true; do
    busybox nc -l -p "$PORT" -e "${MODDIR}/webui_handler.sh" 2>/dev/null
    sleep 0.1
done
