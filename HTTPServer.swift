//
//  HTTPServer.swift
//  CameraCompanion
//
//  HTTP服务器组件 - 负责处理HTTP请求和提供API接口
//

import Network
import Foundation

class HTTPServer {
    private var httpServer: NWListener?
    private weak var cameraManager: CameraManager?
    private weak var imageProcessor: ImageProcessor?
    private weak var videoRecorder: VideoRecorder?
    
    // 数据管理
    private var currentStreamData: Data?
    private var currentCaptureData: Data?
    private let dataLock = NSLock()
    
    // 初始化
    init(cameraManager: CameraManager, imageProcessor: ImageProcessor, videoRecorder: VideoRecorder) {
        self.cameraManager = cameraManager
        self.imageProcessor = imageProcessor
        self.videoRecorder = videoRecorder
    }
    
    // 启动服务器
    func start(port: UInt16 = 8999) {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            httpServer = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            httpServer?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            httpServer?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("HTTP Server started on port \(port)")
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
    
    // 停止服务器
    func stop() {
        httpServer?.cancel()
        httpServer = nil
    }
    
    // 设置流数据
    func setStreamData(_ data: Data) {
        dataLock.lock()
        currentStreamData = data
        dataLock.unlock()
    }
    
    // 设置捕获数据
    func setCaptureData(_ data: Data) {
        dataLock.lock()
        currentCaptureData = data
        dataLock.unlock()
    }
    
    // 处理连接
    private func handleConnection(_ connection: NWConnection) {
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
    
    // 接收请求
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, let request = String(data: data, encoding: .utf8) {
                self?.processRequest(request, connection: connection)
            }
        }
    }
    
    // 处理请求
    private func processRequest(_ request: String, connection: NWConnection) {
        if request.contains("GET /capture") {
            // Single photo
            sendCapture(connection: connection)
        } else if request.contains("GET /stream") {
            // MJPEG stream
            sendStream(connection: connection)
        } else if request.contains("GET /record") {
            // Take a photo and save to desktop
            captureAndSavePhoto(connection: connection)
        } else if request.contains("GET /status") {
            // Camera status
            sendStatus(connection: connection)
        } else if request.contains("GET /video") {
            // Send latest frame as video
            sendVideoFrame(connection: connection)
        } else if request.contains("GET /startRecord") {
            // Start video recording
            startRecording(connection: connection)
        } else if request.contains("GET /stopRecord") {
            // Stop video recording
            stopRecording(connection: connection)
        } else if request.contains("GET /recordingStatus") {
            // Get recording status
            sendRecordingStatus(connection: connection)
        } else {
            // Default response
            sendDefaultResponse(connection: connection)
        }
    }
    
    // 发送拍照响应
    private func sendCapture(connection: NWConnection) {
        capturePhoto()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.dataLock.lock()
            if let data = self.currentCaptureData {
                self.dataLock.unlock()
                self.sendJpeg(data: data, connection: connection)
            } else {
                self.dataLock.unlock()
                self.sendError(connection: connection, message: "Capture failed")
            }
        }
    }
    
    // 拍摄照片
    private func capturePhoto() {
        guard let cameraManager = cameraManager, let imageProcessor = imageProcessor else { return }
        
        if let frame = cameraManager.getCurrentFrame() {
            if let jpegData = imageProcessor.processImage(frame, quality: 0.95) {
                setCaptureData(jpegData)
                print("Photo captured in memory at \(Date())")
            }
        }
    }
    
    // 拍摄并保存照片
    private func captureAndSavePhoto(connection: NWConnection) {
        guard let cameraManager = cameraManager, let imageProcessor = imageProcessor else { 
            sendText(connection: connection, text: "No frame available")
            return
        }
        
        if let frame = cameraManager.getCurrentFrame() {
            let desktopPath = NSHomeDirectory() + "/Desktop/recording.jpg"
            imageProcessor.saveImage(frame, path: desktopPath, quality: 0.95)
            sendText(connection: connection, text: "Photo saved to Desktop/recording.jpg")
        } else {
            sendText(connection: connection, text: "No frame available")
        }
    }
    
    // 发送状态
    private func sendStatus(connection: NWConnection) {
        let status = cameraManager?.captureSession != nil ? "true" : "false"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\",\"camera\":\(status)}"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // 发送视频帧
    private func sendVideoFrame(connection: NWConnection) {
        dataLock.lock()
        if let data = currentStreamData {
            dataLock.unlock()
            sendJpeg(data: data, connection: connection)
        } else {
            dataLock.unlock()
            sendError(connection: connection, message: "No frame available")
        }
    }
    
    // 发送视频流
    private func sendStream(connection: NWConnection) {
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
    
    // 流式发送帧
    private func streamFrames(connection: NWConnection, boundary: String) {
        var lastData: Data?
        
        // Send frames continuously
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard connection.state == .ready else {
                timer.invalidate()
                return
            }
            
            self?.dataLock.lock()
            let currentData = self?.currentStreamData
            self?.dataLock.unlock()
            
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
    
    // 开始录像
    private func startRecording(connection: NWConnection) {
        guard let videoRecorder = videoRecorder else { 
            sendText(connection: connection, text: "Recorder not available")
            return
        }
        
        DispatchQueue.main.async {
            videoRecorder.startRecording()
        }
        sendText(connection: connection, text: "Recording started (60 seconds)")
    }
    
    // 停止录像
    private func stopRecording(connection: NWConnection) {
        guard let videoRecorder = videoRecorder else { 
            sendText(connection: connection, text: "Recorder not available")
            return
        }
        
        DispatchQueue.main.async {
            videoRecorder.stopRecording()
        }
        sendText(connection: connection, text: "Recording stopped")
    }
    
    // 发送录像状态
    private func sendRecordingStatus(connection: NWConnection) {
        guard let videoRecorder = videoRecorder else { 
            sendText(connection: connection, text: "Recorder not available")
            return
        }
        
        let status = videoRecorder.isRecording ? "recording" : "idle"
        let frames = videoRecorder.captureFrameCount
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"\(status)\",\"frames\":\(frames)}"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // 发送默认响应
    private func sendDefaultResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 200 OK
        Content-Type: text/plain; charset=utf-8
        
        🎥 Camera Companion API
        
        Endpoints:
        - GET /capture        - Take photo
        - GET /stream         - MJPEG video stream
        - GET /video          - Single video frame
        - GET /status         - Camera status
        - GET /startRecord    - Start video recording (60s)
        - GET /stopRecord     - Stop recording early
        - GET /recordingStatus - Recording status
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // 发送JPEG数据
    private func sendJpeg(data: Data, connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.count)\r\n\r\n"
        var response = headers.data(using: .utf8)!
        response.append(data)
        
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // 发送错误
    private func sendError(connection: NWConnection, message: String) {
        let response = "HTTP/1.1 500 Error\r\nContent-Type: text/plain\r\n\r\n\(message)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // 发送文本
    private func sendText(connection: NWConnection, text: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n\(text)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}