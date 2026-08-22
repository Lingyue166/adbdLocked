#!/system/bin/sh
# post-fs-data.sh — 开机早期阶段: 初始化 ADB 配置
#
# 在 post-fs-data 阶段运行。根据已保存的模块配置设置 ADB 属性覆盖。

MODDIR="${0%/*}"
. "${MODDIR}/common.sh"

log "post-fs-data.sh 已启动"

# 首次启动时初始化配置
cfg_init

# 如果模式不是关闭状态，则应用 ADB 配置
mode=$(cfg_get mode)
if [ "$mode" != "off" ]; then
    apply_adb_config
    log "开机时已应用 ADB 配置 (模式=$mode)"
fi

log "post-fs-data.sh 已完成"
