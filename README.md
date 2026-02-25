# Mac Camera 伴侣应用

macOS 摄像头应用，支持拍照、视频录制、人脸检测和实时视频流。

## 文件说明

| 文件 | 说明 |
|------|------|
| `CameraCompanionApp.swift` | 主应用代码 |
| `CameraRecorder.swift` | 录像辅助模块 |

## 功能特性

- 📷 **拍照** - 支持拍摄静态照片
- 🎬 **视频录制** - 支持 30/60 秒视频录制
- 👤 **人脸检测** - 自动检测并框选人脸
- 📹 **实时流** - MJPEG 视频流输出
- 🎛 **图像增强** - Photo Booth 风格自然美化
- 🔴 **持续监控** - 24小时不间断监控录制

## 编译运行

```bash
cd /path/to/Mac\ Camera
swiftc -o CameraCompanionApp CameraCompanionApp.swift
./CameraCompanionApp
```

应用启动后在菜单栏显示图标。

## 菜单栏功能

点击菜单栏图标可使用以下功能：

- 📷 拍照
- 🎬 开始录像 / 停止录像
- 🔴 开始监控 / 停止监控 / 监控状态
- 📷 开启摄像头 / 关闭摄像头
- 🚪 退出

## API 接口

| 接口 | 说明 |
|------|------|
| `http://localhost:8999/capture` | 拍摄照片 |
| `http://localhost:8999/stream` | 实时视频流 |
| `http://localhost:8999/startRecord` | 开始录像（60秒） |
| `http://localhost:8999/stopRecord` | 停止录像 |
| `http://localhost:8999/recordingStatus` | 录像状态 |
| `http://localhost:8999/startMonitor` | 开始持续监控 |
| `http://localhost:8999/stopMonitor` | 停止监控 |
| `http://localhost:8999/monitorStatus` | 监控状态 |
| `http://localhost:8999/status` | 相机状态 |

## 使用示例

```bash
# 拍照
curl -s http://localhost:8999/capture -o photo.jpg

# 开始录像
curl -s http://localhost:8999/startRecord

# 停止录像
curl -s http://localhost:8999/stopRecord
```

## 输出文件

- 照片: `~/Desktop/capture.jpg`
- 录像: `~/Desktop/recording.mp4`
- 监控片段: `~/Desktop/monitor_1.mp4`, `monitor_2.mp4`...

## 注意事项

- 只使用 MacBook 内置摄像头，不会调用 iPhone Continuity Camera
- 录像时会自动添加人脸检测绿框
- 实时流支持浏览器直接查看
