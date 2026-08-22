#!/system/bin/sh
# service.sh — 开机完成阶段: 启动守护进程和 WebUI 服务器

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

log "========================================="
log "service.sh 启动 (PID $$)"
log "========================================="

# 等待开机完成
log "步骤 1/5: 等待开机完成 (sys.boot_completed)"
wait_count=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
    wait_count=$((wait_count + 1))
    [ $((wait_count % 30)) -eq 0 ] && log "等待开机完成... 已等待 ${wait_count}秒"
done
log "开机完成，已等待 ${wait_count}秒"

# 额外等待系统服务就绪
log "步骤 2/5: 等待系统服务就绪 (5秒)"
sleep 5

# 初始化配置
log "步骤 3/5: 初始化配置"
cfg_init

# 清理残留进程
log "步骤 4/5: 清理残留进程"
log "    终止旧 daemon.sh..."
pkill -f "daemon.sh" 2>/dev/null
log "    终止旧 webui_server.sh..."
pkill -f "webui_server.sh" 2>/dev/null
log "    终止旧 nc 监听..."
pkill -f "nc.*-l.*-p.*7777" 2>/dev/null
log "    清理残留 FIFO..."
rm -f /tmp/adbdLocked_* 2>/dev/null
log "    清理旧 PID 文件..."
[ -f "$PID_FILE" ] && { rm -f "$PID_FILE"; log "    已删除 daemon.pid"; }
[ -f "$WEBUI_PID_FILE" ] && { rm -f "$WEBUI_PID_FILE"; log "    已删除 webui.pid"; }
sleep 2

# 启动服务
log "步骤 5/5: 启动服务"

log "    启动 WebUI 服务器..."
nohup sh "${MODDIR}/webui_server.sh" >> "${LOG_DIR}/webui.log" 2>&1 &
WEBUI_PID=$!
log "    WebUI 服务器 PID: $WEBUI_PID"

log "    启动守护进程..."
nohup sh "${MODDIR}/daemon.sh" >> "${LOG_DIR}/daemon.log" 2>&1 &
DAEMON_PID=$!
log "    守护进程 PID: $DAEMON_PID"

# 验证进程存活
log "验证进程存活 (3秒后检查)..."
sleep 3

if kill -0 "$DAEMON_PID" 2>/dev/null; then
    log "✅ 守护进程运行正常 (PID $DAEMON_PID)"
else
    log "!!! 错误: 守护进程启动失败 (PID $DAEMON_PID 已退出)"
fi

if kill -0 "$WEBUI_PID" 2>/dev/null; then
    log "✅ WebUI 服务器运行正常 (PID $WEBUI_PID)"
else
    log "!!! 错误: WebUI 服务器启动失败 (PID $WEBUI_PID 已退出)"
fi

log "========================================="
log "service.sh 完成"
log "========================================="
