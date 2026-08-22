# adbdLocked

ADB 无线调试管理模块。保持 adbd 持续运行，熄屏不断开无线连接，通过 WebUI 控制一切。

支持 **Magisk** / **KernelSU** / **Sukisu**。

## 功能

### 三种运行模式

| 模式 | 行为 |
|------|------|
| **开启** | 每 50 秒自动重连所有已知设备 |
| **预备** | 每 5 分钟重连最近使用的无线调试设备 |
| **关闭** | 还原 ADB 默认行为，禁用所有修改 |

### ADB 增强

- **免配对码** — 电脑端输入任意配对码均可通过
- **自定义验证码** — 自定义 6 位数字验证码（带完整校验）
- **锁定配对端口** — 自定义并锁定 ADB 配对端口（1024-65535）
- **局域网免电脑操作** — 随意验证码通过，无须电脑发起连接
- **熄屏保持连接** — 亮屏时已连接的无线调试，熄屏后不断开

### WebUI 控制面板

通过浏览器访问 `http://localhost:7777` 管理所有功能：

- 一键切换运行模式
- 开关功能开关
- 设置验证码和端口
- 查看已连接设备
- 手动连接/断开设备

## 安装

1. 下载 `adbdLocked-v1.0.0.zip`
2. 在 Magisk/KernelSU/Sukisu 中选择「从本地安装」
3. 选择 zip 文件，刷入
4. 重启设备

## 使用

1. 重启后打开浏览器访问 `http://localhost:7777`
2. 选择运行模式（推荐先用「预备」模式测试）
3. 根据需要开启功能开关
4. 设置自定义验证码和端口（可选）

## 目录结构

```
├── module.prop           # 模块元数据
├── common.sh             # 共享工具库
├── daemon.sh             # 后台守护进程
├── webui_server.sh       # WebUI HTTP 服务器
├── webui/
│   └── index.html        # WebUI 界面
├── post-fs-data.sh       # 早期启动初始化
├── service.sh            # 启动守护进程和 WebUI
├── uninstall.sh          # 卸载清理
├── customize.sh          # 安装脚本
├── build.sh              # 构建脚本
└── META-INF/             # Magisk 安装器
```

## 工作原理

- **post-fs-data.sh**: 在开机最早阶段通过 `resetprop` 设置 ADB 属性
- **daemon.sh**: 后台运行，根据模式定期重连设备
- **webui_server.sh**: 轻量 HTTP 服务器，提供 WebUI 和 API
- **uninstall.sh**: 卸载时恢复所有 ADB 默认属性

## 配置文件

配置存储在 `/data/adb/adbdLocked/config.conf`:

```ini
mode=off            # on/standby/off
bypass_pairing=0    # 0/1
custom_code=        # 6位数字
custom_port=        # 1024-65535
auto_approve=0      # 0/1
last_device=        # IP:端口
webui_port=7777     # WebUI 端口
```

## 构建

```bash
chmod +x build.sh
./build.sh
```

## 卸载

在 Magisk/KernelSU/Sukisu 中卸载模块，重启即可。卸载脚本会自动：
- 恢复所有 ADB 属性为原始值
- 终止后台进程
- 清理配置文件

## 许可证

GPL-3.0 — 详见 [LICENSE](LICENSE)
