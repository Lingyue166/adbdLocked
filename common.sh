#!/system/bin/sh
# common.sh — adbdLocked 共享工具库
# 提供: 配置管理、日志记录、屏幕检测、ADB 操作辅助

MODDIR="${0%/*}"

# 仅在 PATH 为空时设置默认 PATH
if [ -z "$PATH" ]; then
    export PATH="/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/system_ext/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/vendor/xbin:/data/adb/ksu/bin"
fi

CFG_DIR="/data/adb/adbdLocked"
CFG_FILE="${CFG_DIR}/config.conf"
LOG_DIR="${CFG_DIR}/logs"
LOG_FILE="${LOG_DIR}/daemon.log"
PID_FILE="${CFG_DIR}/daemon.pid"
WEBUI_PID_FILE="${CFG_DIR}/webui.pid"
DEVICES_FILE="${CFG_DIR}/devices.history"
ORIG_PROPS_FILE="${CFG_DIR}/orig_props.conf"

# ============================================================
# 日志记录（带日志轮转）
# ============================================================
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    echo "[$ts] $1" >> "$LOG_FILE"
    # 保持日志不超过 500 行
    local lines
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$lines" -gt 500 ] && {
        tail -300 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null
        mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
    }
}

# ============================================================
# 错误陷阱 — 任何命令失败都记录行号和命令
# ============================================================
on_error() {
    local exit_code=$?
    local line_no=$1
    local cmd=$2
    log "!!! 错误 [退出码:$exit_code] 行:$line_no 命令:$cmd"
    log "    脚本:$0 PID:$$"
}

# 设置错误陷阱（在每个子脚本中调用）
setup_error_trap() {
    # 使用 DEBUG trap 捕获每个命令的错误
    trap 'on_error $LINENO "$BASH_COMMAND"' ERR
}

# ============================================================
# 崩溃陷阱 — 进程被信号终止时记录
# ============================================================
on_crash() {
    local sig=$1
    log "!!! 崩溃: 收到信号 $sig，脚本 $0 PID $$ 退出"
    log "    堆栈: $(kill -$$ 2>/dev/null; echo "进程已终止")"
}

setup_crash_trap() {
    trap 'on_crash TERM; exit 1' TERM
    trap 'on_crash INT; exit 1' INT
    trap 'on_crash HUP; exit 1' HUP
    trap 'on_crash PIPE; exit 13' PIPE
}

# ============================================================
# 配置管理
# ============================================================
cfg_init() {
    mkdir -p "$CFG_DIR" 2>/dev/null
    if [ ! -f "$CFG_FILE" ]; then
        cat > "$CFG_FILE" <<'EOF'
mode=off
bypass_pairing=0
custom_code=
custom_port=
auto_approve=0
last_device=
webui_port=7777
EOF
        log "已创建默认配置: $CFG_FILE"
    fi
}

cfg_get() {
    grep "^$1=" "$CFG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-
}

cfg_set() {
    local key="$1" val="$2"
    local old_val
    old_val=$(cfg_get "$key")
    if [ "$old_val" = "$val" ]; then
        return 0  # 值未变化，跳过
    fi
    log "配置变更: $key = '$old_val' → '$val'"
    if grep -q "^${key}=" "$CFG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$CFG_FILE"
    else
        echo "${key}=${val}" >> "$CFG_FILE"
    fi
}

# ============================================================
# 屏幕状态检测
# ============================================================
screen_on() {
    local state
    state=$(dumpsys display 2>/dev/null | grep "mScreenState" | head -1)
    case "$state" in
        *ON*) return 0 ;;
        *)    return 1 ;;
    esac
}

# ============================================================
# ADB 属性管理
# ============================================================

save_orig_props() {
    [ -f "$ORIG_PROPS_FILE" ] && return
    log "正在保存原始 ADB 属性..."
    cat > "$ORIG_PROPS_FILE" <<EOF
ro.adb.secure=$(getprop ro.adb.secure)
service.adb.tcp.port=$(getprop service.adb.tcp.port)
persist.sys.adb.tcp.port=$(getprop persist.sys.adb.tcp.port)
EOF
    if [ $? -eq 0 ]; then
        log "已保存原始 ADB 属性: secure=$(getprop ro.adb.secure) port=$(getprop service.adb.tcp.port)"
    else
        log "!!! 错误: 保存原始 ADB 属性失败"
    fi
}

apply_adb_config() {
    local mode
    mode=$(cfg_get mode)
    [ "$mode" = "off" ] && return 1

    log "正在应用 ADB 配置 (模式=$mode)..."
    save_orig_props

    local bypass
    bypass=$(cfg_get bypass_pairing)
    if [ "$bypass" = "1" ]; then
        if resetprop -n ro.adb.secure 0; then
            log "已应用: ro.adb.secure=0 (免配对码)"
        else
            log "!!! 错误: 设置 ro.adb.secure 失败"
        fi
    fi

    local port
    port=$(cfg_get custom_port)
    if [ -n "$port" ]; then
        if resetprop -n service.adb.tcp.port "$port" && resetprop -n persist.sys.adb.tcp.port "$port"; then
            log "已应用: ADB 端口=$port"
        else
            log "!!! 错误: 设置 ADB 端口=$port 失败"
        fi
    fi

    local auto
    auto=$(cfg_get auto_approve)
    if [ "$auto" = "1" ]; then
        if resetprop -n ro.adb.secure 0; then
            log "已应用: 免电脑操作已启用"
        else
            log "!!! 错误: 启用免电脑操作失败"
        fi
        local akey_file="/data/misc/adb/adb_keys"
        if [ -f "$akey_file" ]; then
            grep -q "^.*/" "$akey_file" 2>/dev/null || echo "AAAA" >> "$akey_file"
        fi
    fi

    log "ADB 配置应用完成"
    return 0
}

restore_adb_config() {
    log "正在恢复 ADB 配置..."
    if [ ! -f "$ORIG_PROPS_FILE" ]; then
        log "没有可恢复的属性备份，跳过"
        return 1
    fi

    local orig_secure orig_port orig_pport
    orig_secure=$(grep "^ro.adb.secure=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)
    orig_port=$(grep "^service.adb.tcp.port=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)
    orig_pport=$(grep "^persist.sys.adb.tcp.port=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)

    log "    原始值: secure=$orig_secure port=$orig_port pport=$orig_pport"

    if [ -n "$orig_secure" ]; then
        resetprop -n ro.adb.secure "$orig_secure" && log "    已恢复 ro.adb.secure=$orig_secure" || log "    !!! 恢复 ro.adb.secure 失败"
    else
        resetprop --delete ro.adb.secure 2>/dev/null
    fi

    if [ -n "$orig_port" ]; then
        resetprop -n service.adb.tcp.port "$orig_port" && log "    已恢复 service.adb.tcp.port=$orig_port" || log "    !!! 恢复 service.adb.tcp.port 失败"
    else
        resetprop --delete service.adb.tcp.port 2>/dev/null
    fi

    if [ -n "$orig_pport" ]; then
        resetprop -n persist.sys.adb.tcp.port "$orig_pport" && log "    已恢复 persist.sys.adb.tcp.port=$orig_pport" || log "    !!! 恢复 persist.sys.adb.tcp.port 失败"
    else
        resetprop --delete persist.sys.adb.tcp.port 2>/dev/null
    fi

    rm -f "$ORIG_PROPS_FILE"
    log "ADB 配置恢复完成"
    return 0
}

restart_adbd() {
    log "正在重启 adbd..."
    stop adbd 2>/dev/null
    log "    adbd 已停止"
    sleep 1
    start adbd 2>/dev/null
    log "    adbd 已启动"
    # 验证 adbd 是否存活
    sleep 1
    if pgrep -f adbd >/dev/null 2>&1; then
        log "    adbd 运行正常 (PID: $(pgrep -f adbd | head -1))"
    else
        log "    !!! 警告: adbd 可能未正常启动"
    fi
}

# ============================================================
# 设备管理
# ============================================================

adb_connected_devices() {
    adb devices 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}'
}

adb_history_devices() {
    [ -f "$DEVICES_FILE" ] && cat "$DEVICES_FILE" || echo ""
}

adb_add_device() {
    local device="$1"
    [ -z "$device" ] && return
    mkdir -p "$CFG_DIR" 2>/dev/null
    if ! grep -qF "$device" "$DEVICES_FILE" 2>/dev/null; then
        echo "$device" >> "$DEVICES_FILE"
        log "新设备记录: $device"
    fi
}

adb_connect() {
    local device="$1"
    [ -z "$device" ] && return 1
    log "正在连接设备: $device"
    local result
    result=$(adb connect "$device" 2>&1)
    local rc=$?
    case "$result" in
        *connected*|*already*)
            adb_add_device "$device"
            log "连接成功: $device ($result)"
            return 0
            ;;
        *)
            log "连接失败: $device (rc=$rc 结果=$result)"
            return 1
            ;;
    esac
}

adb_disconnect() {
    local device="$1"
    [ -z "$device" ] && return 1
    log "正在断开设备: $device"
    adb disconnect "$device" 2>/dev/null
    log "已断开: $device"
}

reconnect_all() {
    log "=== 开始全量重连 ==="
    local count=0
    for dev in $(adb_connected_devices); do
        adb_connect "$dev"
        count=$((count + 1))
    done
    for dev in $(adb_history_devices); do
        adb_connect "$dev"
        count=$((count + 1))
    done
    log "=== 全量重连完成: 尝试 $count 台设备 ==="
}

reconnect_last() {
    local last
    last=$(cfg_get last_device)
    if [ -n "$last" ]; then
        log "=== 重连最近设备: $last ==="
        adb_connect "$last"
    else
        log "无最近设备记录，跳过重连"
    fi
}

# ============================================================
# 模块状态描述更新（显示在管理器中）
# ============================================================

update_module_status() {
    local mode screen dev_count mode_name daemon_status
    mode=$(cfg_get mode)

    daemon_status="未运行"
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            daemon_status="运行中"
        fi
    fi

    if screen_on; then
        screen="亮屏"
    else
        screen="熄屏"
    fi

    dev_count=0
    for _ in $(adb_connected_devices); do
        dev_count=$((dev_count + 1))
    done

    case "$mode" in
        on)      mode_name="开启" ;;
        standby) mode_name="预备" ;;
        off)     mode_name="关闭" ;;
        *)       mode_name="$mode" ;;
    esac

    local desc="服务: ${daemon_status} | 模式: ${mode_name} | 屏幕: ${screen} | 设备: ${dev_count}台"

    local prop_file=""
    [ -f "${MODDIR}/module.prop" ] && prop_file="${MODDIR}/module.prop"

    if [ -z "$prop_file" ]; then
        for d in /data/adb/modules/adbdLocked /data/adb/ksu/modules/adbdLocked /data/adb/ap/modules/adbdLocked; do
            [ -f "$d/module.prop" ] && { prop_file="$d/module.prop"; break; }
        done
    fi

    if [ -n "$prop_file" ]; then
        local tmp="${prop_file}.tmp"
        local found=0
        while IFS= read -r line; do
            case "$line" in
                description=*)
                    echo "description=${desc}"
                    found=1
                    ;;
                *)
                    echo "$line"
                    ;;
            esac
        done < "$prop_file" > "$tmp"

        [ "$found" -eq 0 ] && echo "description=${desc}" >> "$tmp"
        mv "$tmp" "$prop_file"
        log "模块描述已更新: $desc"
    else
        log "!!! 警告: 未找到 module.prop，无法更新状态"
    fi
}

# ============================================================
# JSON 辅助（WebUI API 使用）
# ============================================================

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    echo "$s"
}

build_status_json() {
    local mode bypass custom_code custom_port auto_approve last_device webui_port
    local screen_state connected_count connected_list

    mode=$(cfg_get mode)
    bypass=$(cfg_get bypass_pairing)
    custom_code=$(cfg_get custom_code)
    custom_port=$(cfg_get custom_port)
    auto_approve=$(cfg_get auto_approve)
    last_device=$(cfg_get last_device)
    webui_port=$(cfg_get webui_port)

    if screen_on; then
        screen_state="on"
    else
        screen_state="off"
    fi

    connected_list=""
    connected_count=0
    for dev in $(adb_connected_devices); do
        [ -n "$connected_list" ] && connected_list="${connected_list},"
        connected_list="${connected_list}\"${dev}\""
        connected_count=$((connected_count + 1))
    done

    local history_list=""
    for dev in $(adb_history_devices); do
        [ -n "$history_list" ] && history_list="${history_list},"
        history_list="${history_list}\"${dev}\""
    done

    cat <<EOF
{
  "mode": "${mode}",
  "bypass_pairing": ${bypass:-0},
  "custom_code": "${custom_code}",
  "custom_port": "${custom_port}",
  "auto_approve": ${auto_approve:-0},
  "last_device": "${last_device}",
  "screen_state": "${screen_state}",
  "connected_count": ${connected_count},
  "connected_devices": [${connected_list}],
  "history_devices": [${history_list}],
  "webui_port": ${webui_port:-7777}
}
EOF
}
