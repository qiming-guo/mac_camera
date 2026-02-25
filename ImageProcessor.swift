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
    // 缓存CIContext以减少内存使用
    private let ciContext = CIContext()
    
    // 处理图像并返回JPEG数据
    func processImage(_ image: CIImage, quality: CGFloat = 0.95) -> Data? {
        do {
            // 应用图像处理
            let processedImage = try applyImageEnhancement(image)
            
            // 转换为JPEG数据
            return convertToJPEG(processedImage, quality: quality)
        } catch {
            print("Error processing image: \(error)")
            return nil
        }
    }
    
    // 保存图像到文件
    func saveImage(_ image: CIImage, path: String, quality: CGFloat = 0.95) {
        do {
            // 应用图像处理
            let processedImage = try applyImageEnhancement(image)
            
            // 保存到文件
            try saveToFile(processedImage, path: path, quality: quality)
        } catch {
            print("Error saving image: \(error)")
        }
    }
    
    // 应用图像增强
    func applyImageEnhancement(_ image: CIImage) throws -> CIImage {
        // Light enhancement - more natural
        let colorFilter = CIFilter(name: "CIColorControls")
        colorFilter?.setValue(image, forKey: kCIInputImageKey)
        colorFilter?.setValue(0.05, forKey: kCIInputBrightnessKey) // Slight brightness boost
        colorFilter?.setValue(1.05, forKey: kCIInputContrastKey) // Near default
        colorFilter?.setValue(1.0, forKey: kCIInputSaturationKey)
        
        guard var adjustedImage = colorFilter?.outputImage else { 
            throw NSError(domain: "ImageProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to apply color filter"])
        }
        
        // Detect and draw face bounding boxes
        adjustedImage = try detectAndDrawFaces(in: adjustedImage)
        
        // Light sharpening
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")
        sharpenFilter?.setValue(adjustedImage, forKey: kCIInputImageKey)
        sharpenFilter?.setValue(0.3, forKey: kCIInputSharpnessKey) // Light sharpening
        
        guard let finalImage = sharpenFilter?.outputImage else { 
            throw NSError(domain: "ImageProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to apply sharpen filter"])
        }
        
        return finalImage
    }
    
    // 人脸检测和绘制
    private func detectAndDrawFaces(in image: CIImage) throws -> CIImage {
        var resultImage = image
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height
        let originX = image.extent.origin.x
        let originY = image.extent.origin.y
        
        // 使用轻量级的人脸检测请求
        let faceRequest = VNDetectFaceRectanglesRequest()
        
        // 使用 CIImage 创建 VNImageRequestHandler，这样 Vision 框架会使用 CIImage 的坐标系
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            try handler.perform([faceRequest])
            
            guard let observations = faceRequest.results, !observations.isEmpty else {
                return image // No faces detected
            }
            
            for face in observations {
                let boundingBox = face.boundingBox
                // 直接使用 Vision 框架返回的坐标，因为使用了 CIImage 创建 VNImageRequestHandler
                let x = originX + boundingBox.origin.x * imageWidth
                let y = originY + boundingBox.origin.y * imageHeight
                let faceWidth = boundingBox.width * imageWidth
                let faceHeight = boundingBox.height * imageHeight
                
                // Draw green border around face
                let borderWidth: CGFloat = max(4.0, faceWidth * 0.02) // 减小边框宽度以减少内存使用
                let green = CIColor(red: 0, green: 1, blue: 0, alpha: 0.8) // 增加透明度
                
                // 绘制边框
                resultImage = drawBorderAroundFace(in: resultImage, x: x, y: y, width: faceWidth, height: faceHeight, borderWidth: borderWidth, color: green)
            }
        } catch {
            print("Face detection error: \(error)")
            // 人脸检测失败不影响整体处理
        }
        
        return resultImage
    }
    
    // 绘制人脸边框
    private func drawBorderAroundFace(in image: CIImage, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, borderWidth: CGFloat, color: CIColor) -> CIImage {
        var resultImage = image
        
        // 定义边框矩形
        let borders = [
            // Top border
            CGRect(x: x, y: y, width: width, height: borderWidth),
            // Bottom border
            CGRect(x: x, y: y + height - borderWidth, width: width, height: borderWidth),
            // Left border
            CGRect(x: x, y: y, width: borderWidth, height: height),
            // Right border
            CGRect(x: x + width - borderWidth, y: y, width: borderWidth, height: height)
        ]
        
        // 绘制所有边框
        for rect in borders {
            if let filter = CIFilter(name: "CIConstantColorGenerator") {
                filter.setValue(color, forKey: kCIInputColorKey)
                if let borderImage = filter.outputImage?.cropped(to: rect) {
                    resultImage = borderImage.composited(over: resultImage)
                }
            }
        }
        
        return resultImage
    }
    
    // 转换为JPEG数据
    private func convertToJPEG(_ image: CIImage, quality: CGFloat) -> Data? {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        
        // 使用NSBitmapImageRep创建JPEG数据
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: quality]) {
            return jpegData
        }
        
        return nil
    }
    
    // 保存到文件
    private func saveToFile(_ image: CIImage, path: String, quality: CGFloat) throws {
        if let jpegData = convertToJPEG(image, quality: quality) {
            do {
                try jpegData.write(to: URL(fileURLWithPath: path))
                print("Image saved successfully: \(path)")
            } catch {
                throw NSError(domain: "ImageProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Error saving image: \(error.localizedDescription)"])
            }
        } else {
            throw NSError(domain: "ImageProcessor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }
    }
}