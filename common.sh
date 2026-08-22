#!/system/bin/sh
# common.sh — adbdLocked 共享工具库
# 提供: 配置管理、日志记录、屏幕检测、ADB 操作辅助

MODDIR="${0%/*}"

# 确保常用命令在 PATH 中
for p in /system/bin /system/xbin /vendor/bin /data/adb /data/adb/ksu/bin /data/adb/magisk; do
    case ":$PATH:" in *":$p:"*) ;; *) export PATH="$p:$PATH" ;; esac
done

CFG_DIR="/data/adb/adbdLocked"
CFG_FILE="${CFG_DIR}/config.conf"
LOG_DIR="${CFG_DIR}/logs"
LOG_FILE="${LOG_DIR}/daemon.log"
PID_FILE="${CFG_DIR}/daemon.pid"
WEBUI_PID_FILE="${CFG_DIR}/webui.pid"
DEVICES_FILE="${CFG_DIR}/devices.history"
ORIG_PROPS_FILE="${CFG_DIR}/orig_props.conf"

# ============================================================
# 日志记录
# ============================================================
log() {
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    # 保持日志不超过 500 行
    wc -l "$LOG_FILE" 2>/dev/null | grep -q "^500" && {
        tail -300 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    }
}

# ============================================================
# 配置管理
# ============================================================
cfg_init() {
    mkdir -p "$CFG_DIR"
    [ -f "$CFG_FILE" ] || cat > "$CFG_FILE" <<'EOF'
mode=off
bypass_pairing=0
custom_code=
custom_port=
auto_approve=0
last_device=
webui_port=7777
EOF
}

cfg_get() {
    grep "^$1=" "$CFG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-
}

cfg_set() {
    local key="$1" val="$2"
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

# 保存原始 ADB 属性（修改前）
save_orig_props() {
    [ -f "$ORIG_PROPS_FILE" ] && return
    cat > "$ORIG_PROPS_FILE" <<EOF
ro.adb.secure=$(getprop ro.adb.secure)
service.adb.tcp.port=$(getprop service.adb.tcp.port)
persist.sys.adb.tcp.port=$(getprop persist.sys.adb.tcp.port)
EOF
    log "已保存原始 ADB 属性"
}

# 根据当前模块配置应用 ADB 设置
apply_adb_config() {
    local mode
    mode=$(cfg_get mode)
    [ "$mode" = "off" ] && return 1

    save_orig_props

    # 免配对码：关闭安全模式
    local bypass
    bypass=$(cfg_get bypass_pairing)
    if [ "$bypass" = "1" ]; then
        resetprop -n ro.adb.secure 0
        log "已应用: ro.adb.secure=0 (免配对码)"
    fi

    # 自定义端口
    local port
    port=$(cfg_get custom_port)
    if [ -n "$port" ]; then
        resetprop -n service.adb.tcp.port "$port"
        resetprop -n persist.sys.adb.tcp.port "$port"
        log "已应用: ADB 端口=$port"
    fi

    # 免电脑操作：完全关闭认证（与免配对码效果相同）
    local auto
    auto=$(cfg_get auto_approve)
    if [ "$auto" = "1" ]; then
        resetprop -n ro.adb.secure 0
        # 同时向授权密钥文件添加通配符以增强兼容性
        local akey_file="/data/misc/adb/adb_keys"
        if [ -f "$akey_file" ]; then
            # 检查通配符是否已存在
            grep -q "^.*/" "$akey_file" 2>/dev/null || echo "AAAA" >> "$akey_file"
        fi
        log "已应用: 免电脑操作已启用"
    fi

    return 0
}

# 恢复原始 ADB 属性
restore_adb_config() {
    if [ ! -f "$ORIG_PROPS_FILE" ]; then
        log "没有可恢复的属性备份"
        return 1
    fi

    local orig_secure orig_port orig_pport
    orig_secure=$(grep "^ro.adb.secure=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)
    orig_port=$(grep "^service.adb.tcp.port=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)
    orig_pport=$(grep "^persist.sys.adb.tcp.port=" "$ORIG_PROPS_FILE" | cut -d'=' -f2-)

    # 恢复或清除属性
    if [ -n "$orig_secure" ]; then
        resetprop -n ro.adb.secure "$orig_secure"
    else
        resetprop --delete ro.adb.secure 2>/dev/null
    fi

    if [ -n "$orig_port" ]; then
        resetprop -n service.adb.tcp.port "$orig_port"
    else
        resetprop --delete service.adb.tcp.port 2>/dev/null
    fi

    if [ -n "$orig_pport" ]; then
        resetprop -n persist.sys.adb.tcp.port "$orig_pport"
    else
        resetprop --delete persist.sys.adb.tcp.port 2>/dev/null
    fi

    rm -f "$ORIG_PROPS_FILE"
    log "已恢复原始 ADB 属性"
    return 0
}

# 重启 adbd 以应用属性变更
restart_adbd() {
    # 终止 adbd — init 会自动重启它
    stop adbd 2>/dev/null
    sleep 1
    start adbd 2>/dev/null
    log "已重启 adbd"
}

# ============================================================
# 设备管理
# ============================================================

# 获取当前已连接的无线设备
adb_connected_devices() {
    adb devices 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}'
}

# 获取历史设备列表
adb_history_devices() {
    [ -f "$DEVICES_FILE" ] && cat "$DEVICES_FILE" || echo ""
}

# 添加设备到历史记录（去重）
adb_add_device() {
    local device="$1"
    [ -z "$device" ] && return
    mkdir -p "$CFG_DIR"
    if ! grep -qF "$device" "$DEVICES_FILE" 2>/dev/null; then
        echo "$device" >> "$DEVICES_FILE"
        log "已添加设备到历史记录: $device"
    fi
}

# 连接设备
adb_connect() {
    local device="$1"
    [ -z "$device" ] && return 1
    local result
    result=$(adb connect "$device" 2>&1)
    case "$result" in
        *connected*|*already*)
            adb_add_device "$device"
            log "已连接: $device"
            return 0
            ;;
        *)
            log "连接失败: $device ($result)"
            return 1
            ;;
    esac
}

# 断开设备
adb_disconnect() {
    local device="$1"
    [ -z "$device" ] && return 1
    adb disconnect "$device" 2>/dev/null
    log "已断开: $device"
}

# 重连所有已知设备
reconnect_all() {
    local count=0
    # 重连当前已连接的设备
    for dev in $(adb_connected_devices); do
        adb_connect "$dev"
        count=$((count + 1))
    done
    # 同时尝试历史设备
    for dev in $(adb_history_devices); do
        adb_connect "$dev"
        count=$((count + 1))
    done
    log "重连周期: 尝试连接 $count 台设备"
}

# 重连最近使用的设备
reconnect_last() {
    local last
    last=$(cfg_get last_device)
    if [ -n "$last" ]; then
        adb_connect "$last"
        log "重连最近设备: $last"
    else
        log "未配置最近设备"
    fi
}

# ============================================================
# 模块状态描述更新（显示在管理器中）
# ============================================================

# 更新 module.prop 的 description 字段，显示当前运行状态
update_module_status() {
    local mode running screen dev_count mode_name
    mode=$(cfg_get mode)
    running="运行中"
    [ "$mode" = "off" ] && running="已停止"

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

    local desc="状态: ${running} | 模式: ${mode_name} | 屏幕: ${screen} | 设备: ${dev_count}台"

    # 查找 module.prop 文件
    local prop_file=""
    [ -f "${MODDIR}/module.prop" ] && prop_file="${MODDIR}/module.prop"

    # 如果 MODDIR 下没有，尝试在上级 modules 目录查找
    if [ -z "$prop_file" ]; then
        for d in /data/adb/modules/adbdLocked /data/adb/ksu/modules/adbdLocked /data/adb/ap/modules/adbdLocked; do
            [ -f "$d/module.prop" ] && { prop_file="$d/module.prop"; break; }
        done
    fi

    if [ -n "$prop_file" ]; then
        # 逐行重写，避免 sed 在某些 Android 版本上的兼容性问题
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

        # 如果没有 description 行，追加
        [ "$found" -eq 0 ] && echo "description=${desc}" >> "$tmp"

        mv "$tmp" "$prop_file"
        log "已更新模块状态: $desc"
    else
        log "警告: 未找到 module.prop"
    fi
}

# ============================================================
# JSON 辅助（WebUI API 使用）
# ============================================================

# 转义 JSON 字符串
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    echo "$s"
}

# 构建状态 JSON 响应
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

    # 获取已连接设备
    connected_list=""
    connected_count=0
    for dev in $(adb_connected_devices); do
        [ -n "$connected_list" ] && connected_list="${connected_list},"
        connected_list="${connected_list}\"${dev}\""
        connected_count=$((connected_count + 1))
    done

    # 获取历史设备
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
