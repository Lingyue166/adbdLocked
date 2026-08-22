#!/system/bin/sh
# webui_server.sh — WebUI 轻量 HTTP 服务器
# 使用 busybox nc -e 实现，每个连接独立处理

# ============================================================
# 如果带 _handle 参数运行，则作为连接处理器
# ============================================================
if [ "$1" = "_handle" ]; then
    MODDIR="${0%/*}"

    # 最小化 PATH
    [ -z "$PATH" ] && export PATH="/system/bin:/system/xbin:/vendor/bin"

    # 读取请求行
    read -r request_line
    [ -z "$request_line" ] && exit 0

    method=$(echo "$request_line" | awk '{print $1}')
    path=$(echo "$request_line" | awk '{print $2}')

    # 读取请求头
    content_len=0
    while read -r header; do
        header=$(echo "$header" | tr -d '\r')
        [ -z "$header" ] && break
        case "$header" in Content-Length:*) content_len=$(echo "$header" | awk '{print $2}') ;; esac
    done

    # 读取请求体
    body=""
    if [ "$content_len" -gt 0 ] 2>/dev/null; then
        body=$(dd bs=1 count="$content_len" 2>/dev/null)
    fi

    # ---- 配置读写函数 ----
    CFG="/data/adb/adbdLocked/config.conf"
    cfg_get() { grep "^$1=" "$CFG" 2>/dev/null | head -1 | cut -d'=' -f2-; }
    cfg_set() {
        if grep -q "^${1}=" "$CFG" 2>/dev/null; then
            sed -i "s|^${1}=.*|${1}=${2}|" "$CFG"
        else
            echo "${1}=${2}" >> "$CFG"
        fi
    }

    # ---- 响应函数 ----
    json_reply() {
        local status="$1" body="$2" len=${#body}
        printf "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n%s" "$status" "$len" "$body"
    }

    html_reply() {
        local body="$1" len=${#body}
        printf "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n%s" "$len" "$body"
    }

    # ---- 路由 ----
    case "$path" in
        /)
            if [ -f "${MODDIR}/webui/index.html" ]; then
                html_reply "$(cat "${MODDIR}/webui/index.html")"
            else
                json_reply "500 Internal Server Error" "{\"error\":\"文件未找到\"}"
            fi
            ;;
        /api/status)
            # 构建状态 JSON
            mode=$(cfg_get mode)
            bypass=$(cfg_get bypass_pairing)
            auto=$(cfg_get auto_approve)
            code=$(cfg_get custom_code)
            port=$(cfg_get custom_port)
            last=$(cfg_get last_device)
            wport=$(cfg_get webui_port)

            # 屏幕状态
            scr_state=$(dumpsys display 2>/dev/null | grep "mScreenState" | head -1)
            case "$scr_state" in *ON*) scr="on" ;; *) scr="off" ;; esac

            # 设备数
            dev_count=0
            for d in $(adb devices 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}'); do
                dev_count=$((dev_count + 1))
            done

            # 已连接设备列表
            dev_list=""
            for d in $(adb devices 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}'); do
                [ -n "$dev_list" ] && dev_list="${dev_list},"
                dev_list="${dev_list}\"${d}\""
            done

            # 历史设备
            hist_list=""
            if [ -f "/data/adb/adbdLocked/devices.history" ]; then
                for d in $(cat /data/adb/adbdLocked/devices.history 2>/dev/null); do
                    [ -n "$hist_list" ] && hist_list="${hist_list},"
                    hist_list="${hist_list}\"${d}\""
                done
            fi

            json_reply "200 OK" "{\"mode\":\"${mode}\",\"bypass_pairing\":${bypass:-0},\"custom_code\":\"${code}\",\"custom_port\":\"${port}\",\"auto_approve\":${auto:-0},\"last_device\":\"${last}\",\"screen_state\":\"${scr}\",\"connected_count\":${dev_count},\"connected_devices\":[${dev_list}],\"history_devices\":[${hist_list}],\"webui_port\":${wport:-7777}}"
            ;;
        /api/mode)
            new_mode=$(echo "$body" | grep -o 'mode=[^&]*' | cut -d'=' -f2)
            case "$new_mode" in
                on|standby|off)
                    cfg_set mode "$new_mode"
                    json_reply "200 OK" "{\"ok\":true,\"mode\":\"${new_mode}\"}"
                    ;;
                *)
                    json_reply "400 Bad Request" "{\"ok\":false,\"error\":\"无效模式\"}"
                    ;;
            esac
            ;;
        /api/config)
            errors=""

            bypass=$(echo "$body" | grep -o 'bypass_pairing=[^&]*' | cut -d'=' -f2)
            [ -n "$bypass" ] && case "$bypass" in 0|1) cfg_set bypass_pairing "$bypass" ;; *) errors="${errors}bypass无效;" ;; esac

            auto=$(echo "$body" | grep -o 'auto_approve=[^&]*' | cut -d'=' -f2)
            [ -n "$auto" ] && case "$auto" in 0|1) cfg_set auto_approve "$auto" ;; *) errors="${errors}auto无效;" ;; esac

            code=$(echo "$body" | grep -o 'custom_code=[^&]*' | cut -d'=' -f2)
            if [ -n "$code" ]; then
                if [ "$code" = "clear" ]; then cfg_set custom_code ""
                elif [ ${#code} -eq 6 ]; then cfg_set custom_code "$code"
                else errors="${errors}验证码必须6位;"; fi
            fi

            port=$(echo "$body" | grep -o 'custom_port=[^&]*' | cut -d'=' -f2)
            if [ -n "$port" ]; then
                if [ "$port" = "clear" ]; then cfg_set custom_port ""
                elif [ "$port" -ge 1024 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null; then cfg_set custom_port "$port"
                else errors="${errors}端口1024-65535;"; fi
            fi

            last_dev=$(echo "$body" | grep -o 'last_device=[^&]*' | cut -d'=' -f2)
            [ -n "$last_dev" ] && cfg_set last_device "$last_dev"

            if [ -n "$errors" ]; then
                json_reply "200 OK" "{\"ok\":false,\"errors\":\"${errors}\"}"
            else
                json_reply "200 OK" "{\"ok\":true}"
            fi
            ;;
        /api/connect)
            d=$(echo "$body" | grep -o 'device=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g')
            if [ -z "$d" ]; then
                json_reply "400 Bad Request" "{\"ok\":false,\"error\":\"缺少设备\"}"
            else
                r=$(adb connect "$d" 2>&1)
                if [ $? -eq 0 ]; then
                    cfg_set last_device "$d"
                    json_reply "200 OK" "{\"ok\":true,\"result\":\"已连接\"}"
                else
                    json_reply "200 OK" "{\"ok\":false,\"result\":\"${r}\"}"
                fi
            fi
            ;;
        /api/disconnect)
            d=$(echo "$body" | grep -o 'device=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g')
            [ -n "$d" ] && adb disconnect "$d" 2>/dev/null
            json_reply "200 OK" "{\"ok\":true}"
            ;;
        *)
            json_reply "404 Not Found" "{\"ok\":false,\"error\":\"未找到\"}"
            ;;
    esac

    exit 0
fi

# ============================================================
# 主服务器模式
# ============================================================

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

cfg_init

PORT=$(cfg_get webui_port)
PORT=${PORT:-7777}

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
    rm -f "$WEBUI_PID_FILE"
    kill $(jobs -p) 2>/dev/null
    exit 0
}

trap cleanup TERM INT HUP

log "WebUI 服务器已启动，端口 $PORT (PID $$)"
log "正在监听端口 $PORT"

while true; do
    busybox nc -l -p "$PORT" -e "${MODDIR}/webui_server.sh" _handle 2>/dev/null
    sleep 0.1
done
