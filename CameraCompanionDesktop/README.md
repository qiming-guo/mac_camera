# Camera Companion Desktop

Camera Companion Desktop 是一个基于 macOS 菜单栏的桌面应用，用于控制和使用 Camera Companion 服务。

## 功能特点

- 📷 **拍照功能**：通过菜单栏一键拍照，自动保存到应用支持目录
- 🎥 **录像功能**：开始/停止视频录制
- 📹 **视频流**：在浏览器中查看实时视频流
- 🚀 **服务管理**：启动/停止 Camera Companion 服务
- 🔔 **通知提醒**：操作结果实时通知

## 系统要求

- macOS 10.15 或更高版本
- 已编译的 Camera Companion 二进制文件

## 安装和使用

### 1. 准备工作

确保你已经编译了 Camera Companion 服务二进制文件，位于上级目录：

```
../CameraCompanionApp
```

### 2. 编译桌面应用

```bash
# 进入桌面应用目录
cd CameraCompanionDesktop

# 赋予脚本执行权限
chmod +x build.sh run.sh

# 编译应用
./build.sh
```

### 3. 运行应用

```bash
# 运行桌面应用
./run.sh
```

### 4. 使用方法

1. 点击菜单栏中的相机图标
2. 选择「启动服务」启动 Camera Companion 服务
3. 服务启动后，可以使用以下功能：
   - 「拍照」：拍摄照片并保存到 `~/Library/Application Support/CameraCompanion/` 目录
   - 「开始录像」：开始录制视频
   - 「停止录像」：停止录制并保存视频
   - 「查看视频流」：在浏览器中打开视频流
4. 使用完毕后，选择「停止服务」停止 Camera Companion 服务
5. 选择「退出」关闭桌面应用

## 文件结构

```
CameraCompanionDesktop/
├── CameraCompanionDesktopApp.swift  # 主应用代码
├── main.swift                      # 应用入口点
├── build.sh                        # 编译脚本
├── run.sh                          # 运行脚本
└── README.md                       # 使用说明文档
```

## 技术架构

- **主应用**：基于 AppKit 的菜单栏应用
- **服务通信**：通过 HTTP API 与 Camera Companion 服务通信
- **服务管理**：通过 Process 管理 Camera Companion 服务进程
- **用户界面**：简洁的菜单栏下拉菜单
- **通知系统**：使用 NSUserNotification 提供操作反馈

## API 接口

桌面应用通过以下 API 接口与 Camera Companion 服务通信：

- `GET http://localhost:8999/record` - 拍照并保存
- `GET http://localhost:8999/startRecord` - 开始录像
- `GET http://localhost:8999/stopRecord` - 停止录像
- `GET http://localhost:8999/stream` - 视频流

## 保存位置

- **照片**：保存在 `~/Library/Application Support/CameraCompanion/` 目录，文件名格式为 `capture_时间戳.jpg`
- **视频**：保存在 Camera Companion 服务指定的目录

## 注意事项

1. 确保 Camera Companion 服务二进制文件存在于上级目录
2. 服务启动时会占用 8999 端口，请确保该端口未被其他应用占用
3. 首次使用时，系统会请求相机访问权限，请允许访问
4. 应用支持目录会自动创建，无需手动创建

## 故障排除

- **服务启动失败**：检查端口 8999 是否被占用，或 Camera Companion 二进制文件是否存在
- **拍照/录像失败**：检查相机权限是否已授予，或服务是否正常运行
- **视频流无法访问**：检查服务是否正在运行，或浏览器是否支持 MJPEG 流
- **照片保存失败**：检查应用是否有文件系统访问权限

## 许可证

MIT License
