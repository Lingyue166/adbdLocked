#!/system/bin/sh
# post-fs-data.sh — 开机早期阶段: 初始化 ADB 配置

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

log "========================================="
log "post-fs-data.sh 启动 (PID $$)"
log "========================================="

# 初始化配置
log "步骤 1/3: 初始化配置"
cfg_init
if [ $? -eq 0 ]; then
    log "配置初始化成功"
else
    log "!!! 配置初始化失败"
fi

# 读取当前模式
log "步骤 2/3: 读取当前模式"
mode=$(cfg_get mode)
log "当前模式: $mode"

# 应用 ADB 配置
log "步骤 3/3: 应用 ADB 配置"
if [ "$mode" != "off" ]; then
    apply_adb_config
    if [ $? -eq 0 ]; then
        log "ADB 配置应用成功"
    else
        log "ADB 配置应用失败或跳过"
    fi
else
    log "模式为 off，跳过 ADB 配置"
fi

log "========================================="
log "post-fs-data.sh 完成"
log "========================================="
