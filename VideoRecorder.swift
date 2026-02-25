//
//  VideoRecorder.swift
//  CameraCompanion
//
//  视频录制组件 - 负责视频录制和管理
//

import AVFoundation
import AppKit

class VideoRecorder {
    var isRecording = false
    var recordingTimer: Timer?
    var captureFrameCount = 0
    
    // AVAssetWriter for video recording
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: CMTime?
    private weak var cameraManager: CameraManager?
    private weak var imageProcessor: ImageProcessor?
    
    // 初始化
    init(cameraManager: CameraManager, imageProcessor: ImageProcessor) {
        self.cameraManager = cameraManager
        self.imageProcessor = imageProcessor
    }
    
    // 开始录制
    func startRecording() {
        guard !isRecording else { 
            print("Already recording!")
            return 
        }
        
        print("Starting video recording...")
        isRecording = true
        captureFrameCount = 0
        recordingStartTime = nil
        
        // 使用应用支持目录，与照片保存路径一致
        let supportDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSHomeDirectory()
        let appSupportDir = supportDir + "/CameraCompanion"
        
        // 创建目录如果不存在
        do {
            try FileManager.default.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Error creating directory: \(error)")
        }
        
        let outputPath = appSupportDir + "/recording_\(Date().timeIntervalSince1970).mp4"
        
        // Remove existing file
        try? FileManager.default.removeItem(atPath: outputPath)
        
        do {
            // Setup video asset writer
            assetWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputPath), fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            let sourceBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1280,
                kCVPixelBufferHeightKey as String: 720
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: sourceBufferAttributes
            )
            
            if let input = videoInput, assetWriter?.canAdd(input) == true {
                assetWriter?.add(input)
            }
            
            // Setup audio
            setupAudioRecording()
            
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: .zero)
            
            print("Video recording started: \(outputPath)")
            
            // Auto-stop after 60 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.stopRecording()
            }
            
            // Start frame capture timer (30 fps)
            recordingTimer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
                self?.captureVideoFrame()
            }
            RunLoop.main.add(recordingTimer!, forMode: .common)
            
        } catch {
            print("Error starting recording: \(error)")
            isRecording = false
        }
    }
    
    // 停止录制
    func stopRecording() {
        guard isRecording else { return }
        
        print("Stopping recording... (captured \(captureFrameCount) frames)")
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        videoInput?.markAsFinished()
        
        assetWriter?.finishWriting { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 使用应用支持目录，与照片保存路径一致
                let supportDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? NSHomeDirectory()
                let appSupportDir = supportDir + "/CameraCompanion"
                let outputPath = appSupportDir + "/recording_\(Date().timeIntervalSince1970).mp4"
                
                if self.assetWriter?.status == .completed {
                    print("Video saved: \(outputPath)")
                    
                    // Open Finder to show the file
                    NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
                    
                    self.showNotification(title: "录像完成", body: "视频已保存到: \(outputPath)")
                } else {
                    print("Error saving video: \(self.assetWriter?.error?.localizedDescription ?? "unknown")")
                    self.showNotification(title: "录像失败", body: self.assetWriter?.error?.localizedDescription ?? "未知错误")
                }
                
                // Cleanup
                self.assetWriter = nil
                self.videoInput = nil
                self.pixelBufferAdaptor = nil
            }
        }
    }
    
    // 捕获视频帧
    private func captureVideoFrame() {
        guard isRecording, let input = videoInput, input.isReadyForMoreMediaData else { return }
        guard let cameraManager = cameraManager, let imageProcessor = imageProcessor else { return }
        
        if let frame = cameraManager.getCurrentFrame() {
            // Apply face detection to frame
            let frameWithFaces = imageProcessor.applyImageEnhancement(frame)
            
            // Convert CIImage to CVPixelBuffer
            if let pixelBuffer = convertToPixelBuffer(frameWithFaces) {
                let presentationTime = CMTime(value: CMTimeValue(captureFrameCount), timescale: 30)
                
                if recordingStartTime == nil {
                    recordingStartTime = presentationTime
                }
                
                let timeSinceStart = CMTimeSubtract(presentationTime, recordingStartTime!)
                
                if pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timeSinceStart) == true {
                    captureFrameCount += 1
                    if captureFrameCount % 30 == 0 {
                        print("Recording: \(captureFrameCount/30) seconds...")
                    }
                }
            }
        }
    }
    
    // 转换为PixelBuffer
    private func convertToPixelBuffer(_ image: CIImage) -> CVPixelBuffer? {
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
    
    // 设置音频录制
    private func setupAudioRecording() {
        // Request microphone access
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.cameraManager?.setupAudio()
                }
            } else {
                print("Microphone access denied")
            }
        }
    }
    
    // 显示通知
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}