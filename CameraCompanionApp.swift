//
//  CameraCompanionApp.swift
//  CameraCompanion
//
//  OpenClaw 摄像头伴侣应用 - 支持拍照、视频、音频
//

import AppKit
import AVFoundation
import Network
import CoreImage

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // 组件实例
    private var cameraManager: CameraManager!
    private var imageProcessor: ImageProcessor!
    private var videoRecorder: VideoRecorder!
    private var httpServer: HTTPServer!
    
    // 应用程序状态
    private var isRunning = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化组件
        setupComponents()
        
        // 启动相机
        cameraManager.setupCamera { [weak self] success in
            if success {
                self?.startServices()
            } else {
                print("Failed to setup camera")
                self?.quit()
            }
        }
    }
    
    // 初始化组件
    private func setupComponents() {
        // 创建相机管理器
        cameraManager = CameraManager()
        
        // 创建图像处理器
        imageProcessor = ImageProcessor()
        
        // 创建视频录制器
        videoRecorder = VideoRecorder(cameraManager: cameraManager, imageProcessor: imageProcessor)
        
        // 创建HTTP服务器
        httpServer = HTTPServer(cameraManager: cameraManager, imageProcessor: imageProcessor, videoRecorder: videoRecorder)
        
        // 设置相机帧更新回调
        cameraManager.frameUpdateHandler = { [weak self] frame in
            self?.processFrame(frame)
        }
    }
    
    // 启动服务
    private func startServices() {
        // 启动HTTP服务器
        httpServer.start()
        
        // 启动视频流处理
        startVideoStreamProcessing()
        
        isRunning = true
        print("Camera Companion App started successfully")
    }
    
    // 处理相机帧
    private func processFrame(_ frame: CIImage) {
        // 处理视频流帧
        if let jpegData = imageProcessor.processImage(frame, quality: 0.5) {
            httpServer.setStreamData(jpegData)
        }
    }
    
    // 启动视频流处理
    private func startVideoStreamProcessing() {
        // 定时处理视频流
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if let frame = self.cameraManager.getCurrentFrame() {
                self.processFrame(frame)
            }
        }
    }
    
    // 退出应用
    private func quit() {
        // 停止所有服务
        httpServer.stop()
        cameraManager.stopCamera()
        
        isRunning = false
        print("Camera Companion App stopped")
        
        // 退出应用
        NSApplication.shared.terminate(nil)
    }
    
    // 主入口点
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

