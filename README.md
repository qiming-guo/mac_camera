# Mac Camera 伴侣应用

macOS 摄像头应用，支持拍照、视频录制、人脸检测和实时视频流。

## 文件说明

| 文件 | 说明 |
|------|------|
| `CameraCompanionApp.swift` | 主应用代码 |
| `CameraManager.swift` | 相机管理组件 |
| `HTTPServer.swift` | HTTP 服务器组件 |
| `ImageProcessor.swift` | 图像处理和人脸检测组件 |
| `VideoRecorder.swift` | 视频录制组件 |

## 功能特性

- 📷 **拍照** - 支持拍摄静态照片
- 🎬 **视频录制** - 支持 60 秒视频录制
- 👤 **人脸检测** - 自动检测并框选人脸
- 📹 **实时流** - MJPEG 视频流输出
- 🎛 **图像增强** - Photo Booth 风格自然美化

## 编译运行

### 使用脚本编译和运行

项目已包含两个脚本文件，方便编译和运行：

1. **编译脚本** (`build.sh`)
   - 功能：编译所有组件文件，生成可执行文件
   - 执行：
     ```bash
     ./build.sh
     ```

2. **运行脚本** (`run.sh`)
   - 功能：启动编译好的应用程序
   - 执行：
     ```bash
     ./run.sh
     ```

### 使用方法

1. **首次使用**：
   ```bash
   # 编译应用
   ./build.sh
   
   # 运行应用
   ./run.sh
   ```

2. **后续使用**（如果已编译）：
   ```bash
   # 直接运行
   ./run.sh
   ```

3. **重新编译**（如果修改了代码）：
   ```bash
   # 重新编译
   ./build.sh
   
   # 运行
   ./run.sh
   ```

应用启动后在后台运行，通过 HTTP API 提供服务。

## API 接口

| 接口 | 说明 |
|------|------|
| `http://localhost:8999/capture` | 拍摄照片 |
| `http://localhost:8999/stream` | 实时视频流 |
| `http://localhost:8999/startRecord` | 开始录像（60秒） |
| `http://localhost:8999/stopRecord` | 停止录像 |
| `http://localhost:8999/recordingStatus` | 录像状态 |
| `http://localhost:8999/status` | 相机状态 |

## 使用示例

```bash
# 拍照
curl -s http://localhost:8999/capture -o photo.jpg

# 开始录像
curl -s http://localhost:8999/startRecord

# 停止录像
curl -s http://localhost:8999/stopRecord

# 查看录像状态
curl -s http://localhost:8999/recordingStatus

# 查看相机状态
curl -s http://localhost:8999/status
```

## 输出文件

- 照片: 通过 HTTP 响应获取，需手动保存，或通过 `/record` 接口自动保存到 `~/Library/Application Support/CameraCompanion/` 目录
- 录像: `~/Library/Application Support/CameraCompanion/recording_时间戳.mp4`

## 注意事项

- 只使用 MacBook 内置摄像头，不会调用 iPhone Continuity Camera
- 录像时会自动添加人脸检测绿框
- 实时流支持浏览器直接查看
- 应用在后台运行，通过 HTTP API 控制
- 所有功能都通过浏览器或 curl 命令访问
