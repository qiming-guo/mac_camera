//
//  ImageProcessor.swift
//  CameraCompanion
//
//  图像处理组件 - 负责图像增强、人脸检测和图像格式转换
//

import CoreImage
import Vision
import AppKit

class ImageProcessor {
    // 处理图像并返回JPEG数据
    func processImage(_ image: CIImage, quality: CGFloat = 0.95) -> Data? {
        // 应用图像处理
        let processedImage = applyImageEnhancement(image)
        
        // 转换为JPEG数据
        return convertToJPEG(processedImage, quality: quality)
    }
    
    // 保存图像到文件
    func saveImage(_ image: CIImage, path: String, quality: CGFloat = 0.95) {
        // 应用图像处理
        let processedImage = applyImageEnhancement(image)
        
        // 保存到文件
        saveToFile(processedImage, path: path, quality: quality)
    }
    
    // 应用图像增强
    func applyImageEnhancement(_ image: CIImage) -> CIImage {
        // Light enhancement - more natural
        let colorFilter = CIFilter(name: "CIColorControls")
        colorFilter?.setValue(image, forKey: kCIInputImageKey)
        colorFilter?.setValue(0.05, forKey: kCIInputBrightnessKey) // Slight brightness boost
        colorFilter?.setValue(1.05, forKey: kCIInputContrastKey) // Near default
        colorFilter?.setValue(1.0, forKey: kCIInputSaturationKey)
        
        guard var adjustedImage = colorFilter?.outputImage else { return image }
        
        // Detect and draw face bounding boxes
        adjustedImage = detectAndDrawFaces(in: adjustedImage)
        
        // Light sharpening
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")
        sharpenFilter?.setValue(adjustedImage, forKey: kCIInputImageKey)
        sharpenFilter?.setValue(0.3, forKey: kCIInputSharpnessKey) // Light sharpening
        
        guard let finalImage = sharpenFilter?.outputImage else { return adjustedImage }
        
        return finalImage
    }
    
    // 人脸检测和绘制
    private func detectAndDrawFaces(in image: CIImage) -> CIImage {
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
    
    // 转换为JPEG数据
    private func convertToJPEG(_ image: CIImage, quality: CGFloat) -> Data? {
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: quality]) {
            return jpegData
        }
        
        return nil
    }
    
    // 保存到文件
    private func saveToFile(_ image: CIImage, path: String, quality: CGFloat) {
        if let jpegData = convertToJPEG(image, quality: quality) {
            do {
                try jpegData.write(to: URL(fileURLWithPath: path))
                print("Image saved successfully: \(path)")
            } catch {
                print("Error saving image to \(path): \(error)")
            }
        } else {
            print("Failed to create JPEG data for \(path)")
        }
    }
}