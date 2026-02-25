//
//  CameraManager.swift
//  CameraCompanion
//
//  相机管理组件 - 负责摄像头的初始化、配置和数据捕获
//

import AVFoundation
import CoreImage

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    var currentFrame: CIImage?
    let frameLock = NSLock()
    
    // 音频相关
    var audioCaptureDevice: AVCaptureDevice?
    
    // 回调
    var frameUpdateHandler: ((CIImage) -> Void)?
    
    func setupCamera(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    let success = self?.startCamera() ?? false
                    completion(success)
                }
            } else {
                print("Camera permission denied")
                completion(false)
            }
        }
    }
    
    func startCamera() -> Bool {
        guard captureSession == nil else { return true }
        
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
            return false
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
            return true
        } catch {
            print("Camera setup error: \(error)")
            return false
        }
    }
    
    func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
    }
    
    func setupAudio() {
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
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        frameLock.lock()
        currentFrame = ciImage
        frameLock.unlock()
        
        // 回调通知帧更新
        frameUpdateHandler?(ciImage)
    }
    
    func getCurrentFrame() -> CIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return currentFrame
    }
}