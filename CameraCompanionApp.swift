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
import AVKit
import Vision

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var captureSession: AVCaptureSession?
    var httpServer: NWListener?
    var videoOutput: AVCaptureVideoDataOutput?
    var currentFrame: CIImage?
    var currentStreamData: Data?
    var currentCaptureData: Data?
    let capturePath = NSHomeDirectory() + "/Desktop/capture.jpg"
    let frameLock = NSLock()
    
    // Video recording
    var isRecording = false
    var recordingTimer: Timer?
    var captureFrameCount = 0
    
    // AVAssetWriter for video recording
    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var recordingStartTime: CMTime?
    var audioAssetWriter: AVAssetWriter?
    var audioInput: AVAssetWriterInput?
    var audioCaptureDevice: AVCaptureDevice?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupCamera()
        startHTTPServer()
        
        // Start frame saving for video stream
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.saveFrameForStream()
        }
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "📷 Camera"
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "拍照", action: #selector(capturePhoto), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "开始录像", action: #selector(startRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "停止录像", action: #selector(stopRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "开启摄像头", action: #selector(startCamera), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "关闭摄像头", action: #selector(stopCamera), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    func setupCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.main.async {
                    self.startCamera()
                }
            } else {
                print("Camera permission denied")
            }
        }
    }
    
    @objc func startCamera() {
        guard captureSession == nil else { return }
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .hd1280x720
        
        // List available cameras - only built-in to avoid iPhone Continuity Camera
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        print("Available cameras: \(discoverySession.devices.map { $0.localizedName })")
        
        // Use built-in camera only (MacBook FaceTime HD Camera)
        var camera: AVCaptureDevice?
        
        // Prefer front camera (MacBook built-in)
        if let frontCamera = discoverySession.devices.first(where: { $0.position == .front }) {
            camera = frontCamera
            print("Using front camera: \(frontCamera.localizedName)")
        }
        // Fallback to any built-in
        else {
            camera = discoverySession.devices.first
        }
        
        guard let selectedCamera = camera else {
            print("No camera available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: selectedCamera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            // Configure camera for better image
            try selectedCamera.lockForConfiguration()
            if selectedCamera.isExposureModeSupported(.continuousAutoExposure) {
                selectedCamera.exposureMode = .continuousAutoExposure
            }
            if selectedCamera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                selectedCamera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if selectedCamera.isFocusModeSupported(.continuousAutoFocus) {
                selectedCamera.focusMode = .continuousAutoFocus
            }
            selectedCamera.unlockForConfiguration()
            
            // Add video output
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.alwaysDiscardsLateVideoFrames = true
            videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.queue"))
            
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
            captureSession?.startRunning()
            print("Camera started with \(selectedCamera.localizedName)")
        } catch {
            print("Camera setup error: \(error)")
        }
    }
    
    @objc func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    @objc func capturePhoto() {
        frameLock.lock()
        if let frame = currentFrame {
            // Convert frame to JPEG data in memory
            let context = CIContext()
            
            // Light enhancement - more natural
            let colorFilter = CIFilter(name: "CIColorControls")
            colorFilter?.setValue(frame, forKey: kCIInputImageKey)
            colorFilter?.setValue(0.05, forKey: kCIInputBrightnessKey)
            colorFilter?.setValue(1.05, forKey: kCIInputContrastKey)
            colorFilter?.setValue(1.0, forKey: kCIInputSaturationKey)
            
            guard var adjustedImage = colorFilter?.outputImage else {
                frameLock.unlock()
                return
            }
            
            // Detect and draw face bounding boxes
            adjustedImage = detectAndDrawFaces(in: adjustedImage)
            
            // Light sharpening
            let sharpenFilter = CIFilter(name: "CISharpenLuminance")
            sharpenFilter?.setValue(adjustedImage, forKey: kCIInputImageKey)
            sharpenFilter?.setValue(0.3, forKey: kCIInputSharpnessKey)
            
            guard let finalImage = sharpenFilter?.outputImage else {
                frameLock.unlock()
                return
            }
            
            guard let cgImage = context.createCGImage(finalImage, from: finalImage.extent) else {
                frameLock.unlock()
                return
            }
            
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                currentCaptureData = jpegData
                print("Photo captured in memory at \(Date())")
            }
        }
        frameLock.unlock()
    }
    
    @objc func startRecording() {
        guard !isRecording else { 
            print("Already recording!")
            return 
        }
        
        print("Starting video recording...")
        isRecording = true
        captureFrameCount = 0
        recordingStartTime = nil
        
        let outputPath = NSHomeDirectory() + "/Desktop/recording.mp4"
        
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
    
    func setupAudioRecording() {
        // Request microphone access
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.setupAudioInput()
                }
            } else {
                print("Microphone access denied")
            }
        }
    }
    
    func setupAudioInput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("No audio device available")
            return
        }
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            
            // Add audio to existing session if possible
            if let session = captureSession, session.canAddInput(audioInput) {
                session.addInput(audioInput)
                audioCaptureDevice = audioDevice
                print("Audio input added to capture session")
            }
        } catch {
            print("Error setting up audio: \(error)")
        }
    }
    
    func captureVideoFrame() {
        guard isRecording, let input = videoInput, input.isReadyForMoreMediaData else { return }
        
        frameLock.lock()
        guard let frame = currentFrame else {
            frameLock.unlock()
            return
        }
        
        let context = CIContext()
        
        // Apply face detection to frame
        let frameWithFaces = detectAndDrawFaces(in: frame)
        
        guard let cgImage = context.createCGImage(frameWithFaces, from: frameWithFaces.extent) else {
            frameLock.unlock()
            return
        }
        frameLock.unlock()
        
        // Convert CGImage to CVPixelBuffer
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
            return
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
            return
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        let presentationTime = CMTime(value: CMTimeValue(captureFrameCount), timescale: 30)
        
        if recordingStartTime == nil {
            recordingStartTime = presentationTime
        }
        
        let timeSinceStart = CMTimeSubtract(presentationTime, recordingStartTime!)
        
        if pixelBufferAdaptor?.append(buffer, withPresentationTime: timeSinceStart) == true {
            captureFrameCount += 1
            if captureFrameCount % 30 == 0 {
                print("Recording: \(captureFrameCount/30) seconds...")
            }
        }
    }
    
    @objc func stopRecording() {
        guard isRecording else { return }
        
        print("Stopping recording... (captured \(captureFrameCount) frames)")
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        videoInput?.markAsFinished()
        
        assetWriter?.finishWriting { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                let outputPath = NSHomeDirectory() + "/Desktop/recording.mp4"
                
                if self.assetWriter?.status == .completed {
                    print("Video saved: \(outputPath)")
                    
                    // Open Finder to show the file
                    NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
                    
                    self.showNotification(title: "录像完成", body: "视频已保存到桌面: recording.mp4")
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
    
    func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func saveFrameForStream() {
        frameLock.lock()
        if let frame = currentFrame {
            // Convert frame to JPEG data in memory
            let context = CIContext()
            
            // Light enhancement - more natural
            let colorFilter = CIFilter(name: "CIColorControls")
            colorFilter?.setValue(frame, forKey: kCIInputImageKey)
            colorFilter?.setValue(0.05, forKey: kCIInputBrightnessKey)
            colorFilter?.setValue(1.05, forKey: kCIInputContrastKey)
            colorFilter?.setValue(1.0, forKey: kCIInputSaturationKey)
            
            guard var adjustedImage = colorFilter?.outputImage else {
                frameLock.unlock()
                return
            }
            
            // Detect and draw face bounding boxes
            adjustedImage = detectAndDrawFaces(in: adjustedImage)
            
            // Light sharpening
            let sharpenFilter = CIFilter(name: "CISharpenLuminance")
            sharpenFilter?.setValue(adjustedImage, forKey: kCIInputImageKey)
            sharpenFilter?.setValue(0.3, forKey: kCIInputSharpnessKey)
            
            guard let finalImage = sharpenFilter?.outputImage else {
                frameLock.unlock()
                return
            }
            
            guard let cgImage = context.createCGImage(finalImage, from: finalImage.extent) else {
                frameLock.unlock()
                return
            }
            
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) {
                currentStreamData = jpegData
                print("Stream frame saved in memory at \(Date())")
            }
        } else {
            print("No current frame available for stream")
        }
        frameLock.unlock()
    }
    
    func saveEnhancedImage(_ image: CIImage, path: String? = nil, quality: CGFloat = 0.95) {
        let savePath = path ?? capturePath
        
        // Photo Booth style - natural look
        let context = CIContext()
        
        // Light enhancement - more natural
        let colorFilter = CIFilter(name: "CIColorControls")
        colorFilter?.setValue(image, forKey: kCIInputImageKey)
        colorFilter?.setValue(0.05, forKey: kCIInputBrightnessKey) // Slight brightness boost
        colorFilter?.setValue(1.05, forKey: kCIInputContrastKey) // Near default
        colorFilter?.setValue(1.0, forKey: kCIInputSaturationKey)
        
        guard var adjustedImage = colorFilter?.outputImage else { return }
        
        // Detect and draw face bounding boxes
        adjustedImage = detectAndDrawFaces(in: adjustedImage)
        
        // Light sharpening
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")
        sharpenFilter?.setValue(adjustedImage, forKey: kCIInputImageKey)
        sharpenFilter?.setValue(0.3, forKey: kCIInputSharpnessKey) // Light sharpening
        
        guard let finalImage = sharpenFilter?.outputImage else { return }
        
        guard let cgImage = context.createCGImage(finalImage, from: finalImage.extent) else { return }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
            do {
                try jpegData.write(to: URL(fileURLWithPath: savePath))
                print("Image saved successfully: \(savePath)")
            } catch {
                print("Error saving image to \(savePath): \(error)")
            }
        } else {
            print("Failed to create JPEG data for \(savePath)")
        }
    }
    
    func startHTTPServer() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            // Main HTTP server on port 8999
            httpServer = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: 8999))
            
            httpServer?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            httpServer?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("HTTP Server started on port 8999")
                case .failed(let error):
                    print("Server failed: \(error)")
                default:
                    break
                }
            }
            
            httpServer?.start(queue: .main)
        } catch {
            print("Failed to start HTTP server: \(error)")
        }
    }
    
    func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveRequest(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, let request = String(data: data, encoding: .utf8) {
                if request.contains("GET /capture") {
                    // Single photo
                    self?.sendCapture(connection: connection)
                } else if request.contains("GET /stream") {
                    // MJPEG stream
                    self?.sendStream(connection: connection)
                } else if request.contains("GET /record") {
                    // Take a photo and save to desktop
                    self?.frameLock.lock()
                    if let frame = self?.currentFrame {
                        let desktopPath = NSHomeDirectory() + "/Desktop/recording.jpg"
                        self?.saveEnhancedImage(frame, path: desktopPath, quality: 0.95)
                        self?.sendText(connection: connection, text: "Photo saved to Desktop/recording.jpg")
                    } else {
                        self?.sendText(connection: connection, text: "No frame available")
                    }
                    self?.frameLock.unlock()
                } else if request.contains("GET /status") {
                    let status = self?.captureSession != nil ? "true" : "false"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\",\"camera\":\(status)}"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                } else if request.contains("GET /video") {
                    // Send latest frame as video
                    self?.sendVideoFrame(connection: connection)
                } else if request.contains("GET /startRecord") {
                    // Start video recording
                    DispatchQueue.main.async {
                        self?.startRecording()
                    }
                    self?.sendText(connection: connection, text: "Recording started (60 seconds)")
                } else if request.contains("GET /stopRecord") {
                    // Stop video recording
                    DispatchQueue.main.async {
                        self?.stopRecording()
                    }
                    self?.sendText(connection: connection, text: "Recording stopped")
                } else if request.contains("GET /recordingStatus") {
                    // Get recording status
                    let status = self?.isRecording == true ? "recording" : "idle"
                    let frames = self?.captureFrameCount ?? 0
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"\(status)\",\"frames\":\(frames)}"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                } else {
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/plain; charset=utf-8\r
                    \r
                    🎥 Camera Companion API\r
                    \r
                    Endpoints:\r
                    - GET /capture        - Take photo\r
                    - GET /stream         - MJPEG video stream\r
                    - GET /video          - Single video frame\r
                    - GET /status         - Camera status\r
                    - GET /startRecord    - Start video recording (60s)\r
                    - GET /stopRecord     - Stop recording early\r
                    - GET /recordingStatus - Recording status\r
                    """
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }
    }
    
    func sendCapture(connection: NWConnection) {
        capturePhoto()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.frameLock.lock()
            if let data = self?.currentCaptureData {
                self?.frameLock.unlock()
                self?.sendJpeg(data: data, connection: connection)
            } else {
                self?.frameLock.unlock()
                self?.sendError(connection: connection, message: "Capture failed")
            }
        }
    }
    
    func sendVideoFrame(connection: NWConnection) {
        frameLock.lock()
        if let data = currentStreamData {
            frameLock.unlock()
            sendJpeg(data: data, connection: connection)
        } else {
            frameLock.unlock()
            sendError(connection: connection, message: "No frame available")
        }
    }
    
    func sendStream(connection: NWConnection) {
        // Send MJPEG stream
        let boundary = "frame"
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=\(boundary)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        
        if let headerData = headers.data(using: .utf8) {
            connection.send(content: headerData, completion: .contentProcessed { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.streamFrames(connection: connection, boundary: boundary)
                }
            })
        }
    }
    
    func streamFrames(connection: NWConnection, boundary: String) {
        var lastData: Data?
        
        // Send frames continuously
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard connection.state == .ready else {
                timer.invalidate()
                return
            }
            
            self?.frameLock.lock()
            let currentData = self?.currentStreamData
            self?.frameLock.unlock()
            
            if let data = currentData, data != lastData {
                lastData = data
                
                let frameHeader = "--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.count)\r\n\r\n"
                
                if var frameData = frameHeader.data(using: .utf8) {
                    frameData.append(data)
                    frameData.append("\r\n".data(using: .utf8)!)
                    connection.send(content: frameData, completion: .contentProcessed { _ in })
                }
            }
        }
    }
    
    func sendJpeg(data: Data, connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.count)\r\n\r\n"
        var response = headers.data(using: .utf8)!
        response.append(data)
        
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    func sendError(connection: NWConnection, message: String) {
        let response = "HTTP/1.1 500 Error\r\nContent-Type: text/plain\r\n\r\n\(message)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    func sendText(connection: NWConnection, text: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n\(text)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    @objc func quit() {
        stopCamera()
        httpServer?.cancel()
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        frameLock.lock()
        currentFrame = ciImage
        frameLock.unlock()
    }
    
    // MARK: - Face Detection with Expression Analysis
    func detectAndDrawFaces(in image: CIImage) -> CIImage {
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return image }
        
        var resultImage = image
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height
        let originX = image.extent.origin.x
        let originY = image.extent.origin.y
        
        // Use face landmarks request for expression detection (synchronous)
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([landmarksRequest])
            
            guard let observations = landmarksRequest.results as? [VNFaceObservation], !observations.isEmpty else {
                return image // No faces detected
            }
            
            for face in observations {
                let boundingBox = face.boundingBox
                let x = originX + boundingBox.origin.x * imageWidth
                let y = originY + boundingBox.origin.y * imageHeight
                let faceWidth = boundingBox.width * imageWidth
                let faceHeight = boundingBox.height * imageHeight
                
                // Draw green border around face
                let borderWidth: CGFloat = max(8.0, faceWidth * 0.03)
                let green = CIColor(red: 0, green: 1, blue: 0, alpha: 1)
                
                // Top border
                let topRect = CGRect(x: x, y: y + faceHeight - borderWidth, width: faceWidth, height: borderWidth)
                if let filter = CIFilter(name: "CIConstantColorGenerator") {
                    filter.setValue(green, forKey: kCIInputColorKey)
                    if let topImg = filter.outputImage?.cropped(to: topRect) {
                        resultImage = topImg.composited(over: resultImage)
                    }
                }
                // Bottom border
                let bottomRect = CGRect(x: x, y: y, width: faceWidth, height: borderWidth)
                if let filter = CIFilter(name: "CIConstantColorGenerator") {
                    filter.setValue(green, forKey: kCIInputColorKey)
                    if let bottomImg = filter.outputImage?.cropped(to: bottomRect) {
                        resultImage = bottomImg.composited(over: resultImage)
                    }
                }
                // Left border
                let leftRect = CGRect(x: x, y: y, width: borderWidth, height: faceHeight)
                if let filter = CIFilter(name: "CIConstantColorGenerator") {
                    filter.setValue(green, forKey: kCIInputColorKey)
                    if let leftImg = filter.outputImage?.cropped(to: leftRect) {
                        resultImage = leftImg.composited(over: resultImage)
                    }
                }
                // Right border
                let rightRect = CGRect(x: x + faceWidth - borderWidth, y: y, width: borderWidth, height: faceHeight)
                if let filter = CIFilter(name: "CIConstantColorGenerator") {
                    filter.setValue(green, forKey: kCIInputColorKey)
                    if let rightImg = filter.outputImage?.cropped(to: rightRect) {
                        resultImage = rightImg.composited(over: resultImage)
                    }
                }
            }
        } catch {
            print("Face detection error: \(error)")
        }
        
        return resultImage
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
