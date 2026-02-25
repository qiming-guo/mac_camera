import AVFoundation
import AppKit

class CameraRecorder: NSObject {
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var isRecording = false
    var startTime: CMTime?
    
    func listCameras() -> [String] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices.map { $0.localizedName }
    }
    
    func startSession() -> Bool {
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return false }
        
        session.sessionPreset = .hd1920x1080
        
        // Find any available camera
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        guard let camera = discoverySession.devices.first else {
            print("No camera found")
            return false
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if let output = videoOutput, session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
            
            print("Camera started: \(camera.localizedName)")
            return true
        } catch {
            print("Error: \(error)")
            return false
        }
    }
    
    func startRecording(outputURL: URL, duration: Int = 60) {
        guard !isRecording else { return }
        
        do {
            // Remove existing file
            try? FileManager.default.removeItem(at: outputURL)
            
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 10_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            if let input = videoInput, assetWriter?.canAdd(input) == true {
                assetWriter?.add(input)
            }
            
            assetWriter?.startWriting()
            isRecording = true
            startTime = nil
            
            // Setup video output callback
            let queue = DispatchQueue(label: "videoQueue")
            videoOutput?.setSampleBufferDelegate(self, queue: queue)
            
            // Auto-stop after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(duration)) { [weak self] in
                self?.stopRecording()
            }
            
            print("Recording started: \(outputURL.path)")
            
        } catch {
            print("Error starting recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        
        videoInput?.markAsFinished()
        
        assetWriter?.finishWriting { [weak self] in
            guard let self = self else { return }
            if self.assetWriter?.status == .completed {
                print("Recording saved!")
                if let url = self.assetWriter?.outputURL {
                    DispatchQueue.main.async {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                }
            } else {
                print("Error: \(self.assetWriter?.error?.localizedDescription ?? "unknown")")
            }
        }
    }
}

extension CameraRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }
        
        if startTime == nil {
            startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: startTime!)
        }
        
        input.append(sampleBuffer)
    }
}

// Main execution
let recorder = CameraRecorder()

print("Available cameras: \(recorder.listCameras())")

if recorder.startSession() {
    let outputPath = NSHomeDirectory() + "/Desktop/recording.mp4"
    let outputURL = URL(fileURLWithPath: outputPath)
    
    recorder.startRecording(outputURL: outputURL, duration: 60)
    print("Recording for 60 seconds...")
    print("Output: \(outputPath)")
} else {
    print("Failed to start camera")
}

RunLoop.main.run()
