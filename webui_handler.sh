#!/system/bin/sh
# webui_handler.sh — HTTP 请求处理器

MODDIR="${0%/*}"
CFG="/data/adb/adbdLocked/config.conf"
HLOG="/data/adb/adbdLocked/logs/webui.log"
TMPR="/tmp/adbdLocked_resp_$$"

[ -z "$PATH" ] && export PATH="/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin"

hlog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$HLOG" 2>/dev/null; }
cfg_get() { grep "^$1=" "$CFG" 2>/dev/null | head -1 | cut -d'=' -f2-; }
cfg_set() {
    if grep -q "^${1}=" "$CFG" 2>/dev/null; then
        sed -i "s|^${1}=.*|${1}=${2}|" "$CFG"
    else
        echo "${1}=${2}" >> "$CFG"
    fi
}

send_json() {
    local status="$1"
    echo "$2" > "$TMPR"
    local len=$(wc -c < "$TMPR")
    printf "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n" "$status" "$len"
    cat "$TMPR"
    rm -f "$TMPR"
}

send_html() {
    local file="$1"
    local len=$(wc -c < "$file")
    printf "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n" "$len"
    cat "$file"
}

# 读取请求（逐行读取 headers）
request_line=""
content_len=0
body=""
in_body=0

while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')

    if [ $in_body -eq 1 ]; then
        body="${body}${line}"
        continue
    fi

    if [ -z "$request_line" ]; then
        request_line="$line"
        continue
    fi

    if [ -z "$line" ]; then
        # 空行 = headers 结束，开始读 body
        if [ "$content_len" -gt 0 ] 2>/dev/null; then
            in_body=1
        else
            break
        fi
        continue
    fi

    case "$line" in
        Content-Length:*) content_len=$(echo "$line" | awk '{print $2}') ;;
    esac
done

method=$(echo "$request_line" | awk '{print $1}')
full_path=$(echo "$request_line" | awk '{print $2}')
path=$(echo "$full_path" | cut -d'?' -f1)
query=$(echo "$full_path" | cut -d'?' -f2-)
# GET 参数和 POST body 合并处理
if [ -n "$query" ]; then
    [ -n "$body" ] && body="${query}&${body}" || body="$query"
fi
hlog "请求: $method $path (body=$body)"

# 路由
case "$path" in

    /)
        if [ -f "${MODDIR}/webui/index.html" ]; then
            send_html "${MODDIR}/webui/index.html"
            hlog "响应: 200 HTML"
        else
            send_json "500 Internal Server Error" '{"error":"文件未找到"}'
            hlog "响应: 500 文件未找到"
        fi
        ;;

    /api/status)
        mode=$(cfg_get mode)
        bypass=$(cfg_get bypass_pairing)
        auto=$(cfg_get auto_approve)
        code=$(cfg_get custom_code)
        port=$(cfg_get custom_port)
        last=$(cfg_get last_device)
        wport=$(cfg_get webui_port)

        scr_state=$(dumpsys display 2>/dev/null | grep "mScreenState" | head -1)
        case "$scr_state" in *ON*) scr="on" ;; *) scr="off" ;; esac

        dev_count=0; dev_list=""
        for d in $(adb devices 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}'); do
            dev_count=$((dev_count + 1))
            [ -n "$dev_list" ] && dev_list="${dev_list},"
            dev_list="${dev_list}\"${d}\""
        done

        hist_list=""
        if [ -f "/data/adb/adbdLocked/devices.history" ]; then
            for d in $(cat /data/adb/adbdLocked/devices.history 2>/dev/null); do
                [ -n "$hist_list" ] && hist_list="${hist_list},"
                hist_list="${hist_list}\"${d}\""
            done
        fi

        send_json "200 OK" "{\"mode\":\"${mode}\",\"bypass_pairing\":${bypass:-0},\"custom_code\":\"${code}\",\"custom_port\":\"${port}\",\"auto_approve\":${auto:-0},\"last_device\":\"${last}\",\"screen_state\":\"${scr}\",\"connected_count\":${dev_count},\"connected_devices\":[${dev_list}],\"history_devices\":[${hist_list}],\"webui_port\":${wport:-7777}}"
        hlog "响应: 200 状态"
        ;;

    /api/mode)
        new_mode=$(echo "$body" | grep -o 'mode=[^&]*' | cut -d'=' -f2)
        case "$new_mode" in
            on|standby|off)
                cfg_set mode "$new_mode"
                send_json "200 OK" "{\"ok\":true,\"mode\":\"${new_mode}\"}"
                hlog "响应: 200 模式=$new_mode"
                ;;
            *)
                send_json "400 Bad Request" '{"ok":false,"error":"无效模式"}'
                hlog "响应: 400 无效模式"
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
            send_json "200 OK" "{\"ok\":false,\"errors\":\"${errors}\"}"
            hlog "响应: 200 配置错误: $errors"
        else
            send_json "200 OK" '{"ok":true}'
            hlog "响应: 200 配置更新"
        fi
        ;;

    /api/connect)
        d=$(echo "$body" | grep -o 'device=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g')
        if [ -z "$d" ]; then
            send_json "400 Bad Request" '{"ok":false,"error":"缺少设备"}'
            hlog "响应: 400 缺少设备"
        else
            res=$(adb connect "$d" 2>&1)
            if [ $? -eq 0 ]; then
                cfg_set last_device "$d"
                send_json "200 OK" '{"ok":true,"result":"已连接"}'
                hlog "响应: 200 已连接 $d"
            else
                send_json "200 OK" "{\"ok\":false,\"result\":\"${res}\"}"
                hlog "响应: 200 连接失败 $d"
            fi
        fi
        ;;

    /api/disconnect)
        d=$(echo "$body" | grep -o 'device=[^&]*' | cut -d'=' -f2 | sed 's/%3A/:/g')
        [ -n "$d" ] && adb disconnect "$d" 2>/dev/null
        send_json "200 OK" '{"ok":true}'
        hlog "响应: 200 断开 $d"
        ;;

    *)
        send_json "404 Not Found" '{"ok":false,"error":"未找到"}'
        hlog "响应: 404 $path"
        ;;
esac

exit 0
