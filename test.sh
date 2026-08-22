#!/system/bin/sh
# test.sh — adbdLocked 单元测试
# 在设备上运行: sh /data/adb/modules/adbdLocked/test.sh

LOG="/data/adb/adbdLocked/logs/test.log"
CFG="/data/adb/adbdLocked/config.conf"

mkdir -p "$(dirname "$LOG")"

# 测试计数
PASS=0
FAIL=0
TOTAL=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

test_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    log "  ✅ 通过: $1"
}

test_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    log "  ❌ 失败: $1"
}

test_check() {
    if [ "$1" = "0" ]; then
        test_pass "$2"
    else
        test_fail "$2 (退出码: $1)"
    fi
}

# HTTP 请求辅助（使用 GET 参数，避免 POST body 问题）
http_get() {
    local req_file="/tmp/adbdLocked_test_req"
    printf 'GET %s HTTP/1.0\r\nHost: localhost\r\n\r\n' "$1" > "$req_file"
    cat "$req_file" | busybox nc -w 3 localhost 7777 2>/dev/null
    rm -f "$req_file"
    sleep 1
}

http_post() {
    # 使用 GET 参数代替 POST body
    local path="$1" body="$2"
    http_get "${path}?${body}"
}

# ============================================================
log "========================================="
log "adbdLocked 单元测试开始"
log "========================================="

# ============================================================
log ""
log ">>> 测试 1: 进程检查"
# ============================================================

if pgrep -f "daemon.sh" >/dev/null 2>&1; then
    test_pass "守护进程运行中 (PID: $(pgrep -f daemon.sh | head -1))"
else
    test_fail "守护进程未运行"
fi

if pgrep -f "webui_server.sh" >/dev/null 2>&1; then
    test_pass "WebUI 服务器运行中 (PID: $(pgrep -f webui_server.sh | head -1))"
else
    test_fail "WebUI 服务器未运行"
fi

if pgrep -f "nc.*-l.*-p.*7777" >/dev/null 2>&1; then
    test_pass "nc 监听端口 7777"
else
    test_fail "nc 未监听端口 7777"
fi

# ============================================================
log ""
log ">>> 测试 2: 端口检查"
# ============================================================

if netstat -tlnp 2>/dev/null | grep -q ":7777.*LISTEN"; then
    test_pass "端口 7777 正在监听"
else
    test_fail "端口 7777 未监听"
fi

# ============================================================
log ""
log ">>> 测试 3: 配置文件检查"
# ============================================================

if [ -f "$CFG" ]; then
    test_pass "配置文件存在: $CFG"
else
    test_fail "配置文件不存在: $CFG"
fi

mode=$(grep "^mode=" "$CFG" 2>/dev/null | cut -d'=' -f2)
if [ -n "$mode" ]; then
    test_pass "配置读取正常: mode=$mode"
else
    test_fail "无法读取配置 mode"
fi

# ============================================================
log ""
log ">>> 测试 4: API /api/status"
# ============================================================

resp=$(http_get "/api/status")
if [ -n "$resp" ]; then
    if echo "$resp" | grep -q '"mode"'; then
        test_pass "API /api/status 响应包含 mode 字段"
    else
        test_fail "API /api/status 响应缺少 mode 字段"
    fi

    if echo "$resp" | grep -q '"screen_state"'; then
        test_pass "API /api/status 响应包含 screen_state 字段"
    else
        test_fail "API /api/status 响应缺少 screen_state 字段"
    fi

    # 检查 Content-Length 是否正确
    cl=$(echo "$resp" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r')
    if [ -n "$cl" ] && [ "$cl" -gt 0 ] 2>/dev/null; then
        test_pass "Content-Length > 0: $cl"
    else
        test_fail "Content-Length 无效: $cl"
    fi
else
    test_fail "API /api/status 无响应"
fi

# ============================================================
log ""
log ">>> 测试 5: API / 页面"
# ============================================================

resp=$(http_get "/")
if [ -n "$resp" ]; then
    if echo "$resp" | grep -q "adbdLocked"; then
        test_pass "HTML 页面包含 adbdLocked"
    else
        test_fail "HTML 页面缺少 adbdLocked"
    fi

    cl=$(echo "$resp" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r')
    if [ -n "$cl" ] && [ "$cl" -gt 0 ] 2>/dev/null; then
        test_pass "HTML Content-Length > 0: $cl"
    else
        test_fail "HTML Content-Length 无效: $cl"
    fi
else
    test_fail "HTML 页面无响应"
fi

# ============================================================
log ""
log ">>> 测试 6: API /api/mode"
# ============================================================

# 保存原始模式
orig_mode=$(grep "^mode=" "$CFG" 2>/dev/null | cut -d'=' -f2)

# 切换到 standby
resp=$(http_post "/api/mode" "mode=standby")
if echo "$resp" | grep -q '"ok":true'; then
    test_pass "模式切换到 standby 成功"
else
    test_fail "模式切换到 standby 失败"
fi

# 验证配置已更新
new_mode=$(grep "^mode=" "$CFG" 2>/dev/null | cut -d'=' -f2)
if [ "$new_mode" = "standby" ]; then
    test_pass "配置已更新为 standby"
else
    test_fail "配置未更新 (当前: $new_mode)"
fi

# 切换回原模式
http_post "/api/mode" "mode=$orig_mode" >/dev/null 2>&1

# ============================================================
log ""
log ">>> 测试 7: API /api/config"
# ============================================================

# 测试设置验证码
resp=$(http_post "/api/config" "custom_code=123456")
if echo "$resp" | grep -q '"ok":true'; then
    test_pass "设置验证码 123456 成功"
else
    test_fail "设置验证码失败"
fi

# 测试无效验证码
resp=$(http_post "/api/config" "custom_code=abc")
if echo "$resp" | grep -q '验证码必须6位'; then
    test_pass "无效验证码被正确拒绝"
else
    test_fail "无效验证码未被拒绝"
fi

# 测试设置端口
resp=$(http_post "/api/config" "custom_port=5555")
if echo "$resp" | grep -q '"ok":true'; then
    test_pass "设置端口 5555 成功"
else
    test_fail "设置端口失败"
fi

# 测试无效端口
resp=$(http_post "/api/config" "custom_port=99999")
if echo "$resp" | grep -q '端口1024-65535'; then
    test_pass "无效端口被正确拒绝"
else
    test_fail "无效端口未被拒绝"
fi

# ============================================================
log ""
log ">>> 测试 8: module.prop 状态"
# ============================================================

prop_desc=$(grep "^description=" /data/adb/modules/adbdLocked/module.prop 2>/dev/null | cut -d'=' -f2-)
if [ -n "$prop_desc" ]; then
    if echo "$prop_desc" | grep -q "服务:"; then
        test_pass "module.prop 包含服务状态: $prop_desc"
    else
        test_fail "module.prop 缺少服务状态"
    fi
else
    test_fail "module.prop 无 description"
fi

# ============================================================
log ""
log ">>> 测试 9: 日志文件"
# ============================================================

if [ -f "/data/adb/adbdLocked/logs/daemon.log" ]; then
    lines=$(wc -l < /data/adb/adbdLocked/logs/daemon.log)
    test_pass "daemon.log 存在 ($lines 行)"
else
    test_fail "daemon.log 不存在"
fi

if [ -f "/data/adb/adbdLocked/logs/webui.log" ]; then
    lines=$(wc -l < /data/adb/adbdLocked/logs/webui.log)
    test_pass "webui.log 存在 ($lines 行)"
else
    test_fail "webui.log 不存在"
fi

# ============================================================
log ""
log "========================================="
log "测试完成: 总计 $TOTAL | 通过 $PASS | 失败 $FAIL"
log "========================================="

# 输出测试报告到文件
{
    echo "adbdLocked 单元测试报告"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "总计: $TOTAL"
    echo "通过: $PASS"
    echo "失败: $FAIL"
    echo "通过率: $((PASS * 100 / TOTAL))%"
    echo ""
    echo "详细日志: $LOG"
} > /data/adb/adbdLocked/logs/test_report.txt

log "报告已保存: /data/adb/adbdLocked/logs/test_report.txt"
