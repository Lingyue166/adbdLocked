#!/system/bin/sh
# webui_server.sh — WebUI 轻量 HTTP 服务器
#
# 使用命名管道实现与 nc 的双向通信

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

# ============================================================
# 初始化
# ============================================================

cfg_init

PORT=$(cfg_get webui_port)
PORT=${PORT:-7777}

# 防止重复启动
if [ -f "$WEBUI_PID_FILE" ]; then
    old_pid=$(cat "$WEBUI_PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log "WebUI 服务器已在运行 (PID $old_pid)，退出"
        exit 0
    fi
fi

echo $$ > "$WEBUI_PID_FILE"

# 命名管道
FIFO="/tmp/adbdLocked_fifo_$$"
rm -f "$FIFO"
mkfifo "$FIFO"

cleanup() {
    log "WebUI 服务器正在关闭"
    rm -f "$WEBUI_PID_FILE" "$FIFO"
    exit 0
}

trap cleanup TERM INT HUP

log "WebUI 服务器已启动，端口 $PORT (PID $$)"

# ============================================================
# HTTP 辅助函数
# ============================================================

send_response() {
    local status="$1" content_type="$2" body="$3"
    local body_len=${#body}
    printf "HTTP/1.1 %s\r\n" "$status"
    printf "Content-Type: %s\r\n" "$content_type"
    printf "Content-Length: %d\r\n" "$body_len"
    printf "Connection: close\r\n"
    printf "Access-Control-Allow-Origin: *\r\n"
    printf "\r\n"
    printf "%s" "$body"
}

send_json() { send_response "200 OK" "application/json" "$1"; }
send_html() { send_response "200 OK" "text/html; charset=utf-8" "$1"; }
send_error() { send_response "$1 $2" "application/json" "{\"error\":\"$2\"}"; }

# ============================================================
# 输入校验
# ============================================================

validate_code() {
    local code="$1"
    [ ${#code} -ne 6 ] && { echo "验证码必须为6位"; return 1; }
    local i=0
    while [ $i -lt 6 ]; do
        case "${code:$i:1}" in [0-9]) ;; *) echo "验证码只能包含数字"; return 1 ;; esac
        i=$((i + 1))
    done
}

validate_port() {
    local port="$1"
    case "$port" in *[!0-9]*|"") echo "端口号必须为数字"; return 1 ;; esac
    [ "$port" -lt 1024 ] && { echo "端口号不能小于1024"; return 1; }
    [ "$port" -gt 65535 ] && { echo "端口号不能大于65535"; return 1; }
}

# ============================================================
# API 处理
# ============================================================

handle_api_status() { send_json "$(build_status_json)"; }

handle_api_mode() {
    case "$1" in
        on|standby|off) cfg_set mode "$1"; log "模式已切换为: $1"; send_json "{\"ok\":true,\"mode\":\"$1\"}" ;;
        *) send_error 400 "无效模式" ;;
    esac
}

handle_api_config() {
    local body="$1" errors=""

    local bypass=$(echo "$body" | grep -o 'bypass_pairing=[^&]*' | cut -d'=' -f2)
    [ -n "$bypass" ] && case "$bypass" in 0|1) cfg_set bypass_pairing "$bypass" ;; *) errors="${errors}bypass_pairing无效;" ;; esac

    local auto=$(echo "$body" | grep -o 'auto_approve=[^&]*' | cut -d'=' -f2)
    [ -n "$auto" ] && case "$auto" in 0|1) cfg_set auto_approve "$auto" ;; *) errors="${errors}auto_approve无效;" ;; esac

    local code=$(echo "$body" | grep -o 'custom_code=[^&]*' | cut -d'=' -f2)
    if [ -n "$code" ]; then
        if [ "$code" = "clear" ]; then cfg_set custom_code ""
        else local e; e=$(validate_code "$code"); [ $? -ne 0 ] && errors="${errors}${e};" || cfg_set custom_code "$code"; fi
    fi

    local port=$(echo "$body" | grep -o 'custom_port=[^&]*' | cut -d'=' -f2)
    if [ -n "$port" ]; then
        if [ "$port" = "clear" ]; then cfg_set custom_port ""
        else local e; e=$(validate_port "$port"); [ $? -ne 0 ] && errors="${errors}${e};" || cfg_set custom_port "$port"; fi
    fi

    local last=$(echo "$body" | grep -o 'last_device=[^&]*' | cut -d'=' -f2)
    [ -n "$last" ] && cfg_set last_device "$last"

    [ -n "$errors" ] && { send_json "{\"ok\":false,\"errors\":\"${errors}\"}"; return; }
    local m; m=$(cfg_get mode); [ "$m" != "off" ] && apply_adb_config
    send_json "{\"ok\":true}"
}

handle_api_connect() {
    [ -z "$1" ] && { send_error 400 "缺少设备参数"; return; }
    local r; r=$(adb_connect "$1" 2>&1)
    [ $? -eq 0 ] && { cfg_set last_device "$1"; send_json "{\"ok\":true,\"result\":\"已连接\"}"; } || send_json "{\"ok\":false,\"result\":\"${r}\"}"
}

handle_api_disconnect() {
    [ -z "$1" ] && { send_error 400 "缺少设备参数"; return; }
    adb_disconnect "$1"
    send_json "{\"ok\":true}"
}

# ============================================================
# 请求路由
# ============================================================

handle_request() {
    local method="$1" path="$2" body="$3"
    [ "$method" = "OPTIONS" ] && { printf "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\n\r\n"; return; }
    case "$path" in
        /) [ -f "${MODDIR}/webui/index.html" ] && send_html "$(cat "${MODDIR}/webui/index.html")" || send_error 500 "文件未找到" ;;
        /api/status) handle_api_status ;;
        /api/mode) handle_api_mode "$(echo "$body" | grep -o 'mode=[^&]*' | cut -d'=' -f2)" ;;
        /api/config) handle_api_config "$body" ;;
        /api/connect) local d; d=$(echo "$body" | grep -o 'device=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g'); handle_api_connect "$d" ;;
        /api/disconnect) local d; d=$(echo "$body" | grep -o 'device=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g'); handle_api_disconnect "$d" ;;
        *) send_error 404 "未找到" ;;
    esac
}

# ============================================================
# 请求处理循环（通过命名管道与 nc 通信）
# ============================================================

log "WebUI 服务器正在监听端口 $PORT"

while true; do
    # nc 从 FIFO 读取响应发送给客户端，同时将客户端请求输出到 stdout
    # 我们将 nc 的 stdout 重定向到 stdin，形成双向通信
    (cat "$FIFO") | nc -l -p "$PORT" | (
        read -r request_line
        [ -z "$request_line" ] && exit 0

        method=$(echo "$request_line" | awk '{print $1}')
        path=$(echo "$request_line" | awk '{print $2}')

        content_len=0
        while read -r header; do
            header=$(echo "$header" | tr -d '\r')
            [ -z "$header" ] && break
            case "$header" in Content-Length:*) content_len=$(echo "$header" | awk '{print $2}') ;; esac
        done

        body=""
        [ "$content_len" -gt 0 ] 2>/dev/null && body=$(dd bs=1 count="$content_len" 2>/dev/null)

        # 将响应写入 FIFO（nc 从 FIFO 读取并发送给客户端）
        handle_request "$method" "$path" "$body" > "$FIFO"
    ) &

    # 等待当前请求处理完成
    wait $! 2>/dev/null
    sleep 0.1
done
