//
//  ImageProcessor.swift
//  CameraCompanion
//
//  图像处理组件 - 负责图像增强、人脸检测和图像格式转换
//

import CoreImage
import Vision
import AppKit
import QuartzCore

// 扩展 CALayer 以添加 renderedImage 方法
extension CALayer {
    func renderedImage() -> CGImage {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let bytesPerRow = width * 4
        
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        
        render(in: context)
        
        return context.makeImage()!
    }
}

class ImageProcessor {
    // 缓存CIContext以减少内存使用
    private let ciContext = CIContext()
    
    // 人脸库
    private var faceLibrary: [String: [VNFaceObservation]] = [:]
    
    init() {
        // 加载人脸库
        loadFaceLibrary()
    }
    
    // 加载人脸库
    private func loadFaceLibrary() {
        let faceLibsPath = "FaceLibs"
        let fileManager = FileManager.default
        
        guard let items = try? fileManager.contentsOfDirectory(atPath: faceLibsPath) else {
            print("No files in FaceLibs directory")
            return
        }
        
        for item in items {
            let filePath = "\(faceLibsPath)/\(item)"
            
            // 只处理图片文件
            let fileExtension = URL(fileURLWithPath: item).pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "tiff"].contains(fileExtension) {
                // 加载图片
                if let image = NSImage(contentsOfFile: filePath) {
                    // 检测人脸
                    if let faceObservations = detectFacesInImage(image) {
                        // 存储人脸特征，使用文件名（不含扩展名）作为键
                        let fileNameWithoutExtension = (item as NSString).deletingPathExtension
                        faceLibrary[fileNameWithoutExtension] = faceObservations
                        print("Loaded face for: \(fileNameWithoutExtension)")
                    }
                }
            }
        }
        
        print("Face library loaded with \(faceLibrary.count) entries")
    }
    
    // 在图片中检测人脸
    private func detectFacesInImage(_ image: NSImage) -> [VNFaceObservation]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([faceRequest])
            return faceRequest.results
        } catch {
            print("Error detecting faces in library image: \(error)")
            return nil
        }
    }
    
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
                
                // 识别人脸
                let personName = identifyPerson(face: face)
                
                // Draw green border around face
                let borderWidth: CGFloat = max(4.0, faceWidth * 0.02) // 减小边框宽度以减少内存使用
                let green = CIColor(red: 0, green: 1, blue: 0, alpha: 0.8) // 增加透明度
                
                // 绘制边框
                resultImage = drawBorderAroundFace(in: resultImage, x: x, y: y, width: faceWidth, height: faceHeight, borderWidth: borderWidth, color: green)
                
                // 如果识别出人物，在边框上方显示人名
                if let name = personName {
                    resultImage = drawText(in: resultImage, text: name, x: x, y: y - 20, width: faceWidth, color: green)
                }
            }
        } catch {
            print("Face detection error: \(error)")
            // 人脸检测失败不影响整体处理
        }
        
        return resultImage
    }
    
    // 识别人脸
    private func identifyPerson(face: VNFaceObservation) -> String? {
        // 简单的人脸识别逻辑：比较人脸框的位置和大小
        // 在实际应用中，应该使用更复杂的人脸识别算法
        
        // 打印调试信息
        print("Current face: x=\(face.boundingBox.origin.x), y=\(face.boundingBox.origin.y), width=\(face.boundingBox.width), height=\(face.boundingBox.height)")
        
        // 如果人脸库为空，直接返回 nil
        if faceLibrary.isEmpty {
            print("Face library is empty")
            return nil
        }
        
        // 计算当前人脸的中心点和大小
        let currentFaceCenterX = face.boundingBox.origin.x + face.boundingBox.width / 2
        let currentFaceCenterY = face.boundingBox.origin.y + face.boundingBox.height / 2
        let currentFaceSize = face.boundingBox.width * face.boundingBox.height
        
        print("Current face center: (\(currentFaceCenterX), \(currentFaceCenterY)), size: \(currentFaceSize)")
        
        // 遍历人脸库，寻找最匹配的人脸
        var bestMatch: String? = nil
        var bestScore = 0.0
        
        for (personName, faceObservations) in faceLibrary {
            print("Checking person: \(personName)")
            for (index, libraryFace) in faceObservations.enumerated() {
                // 计算库中人脸的中心点和大小
                let libraryFaceCenterX = libraryFace.boundingBox.origin.x + libraryFace.boundingBox.width / 2
                let libraryFaceCenterY = libraryFace.boundingBox.origin.y + libraryFace.boundingBox.height / 2
                let libraryFaceSize = libraryFace.boundingBox.width * libraryFace.boundingBox.height
                
                print("  Library face \(index): x=\(libraryFace.boundingBox.origin.x), y=\(libraryFace.boundingBox.origin.y), width=\(libraryFace.boundingBox.width), height=\(libraryFace.boundingBox.height)")
                print("  Library face center: (\(libraryFaceCenterX), \(libraryFaceCenterY)), size: \(libraryFaceSize)")
                
                // 计算相似度分数（距离越小，相似度越高）
                let distance = sqrt(pow(currentFaceCenterX - libraryFaceCenterX, 2) + pow(currentFaceCenterY - libraryFaceCenterY, 2))
                let sizeDifference = abs(currentFaceSize - libraryFaceSize) / currentFaceSize
                let score = 1.0 / (distance + sizeDifference + 0.1) // 添加一个小值避免除以零
                
                print("  Score: \(score)")
                
                // 更新最佳匹配
                if score > bestScore {
                    bestScore = score
                    bestMatch = personName
                    print("  New best match: \(personName) with score \(bestScore)")
                }
            }
        }
        
        // 打印最终结果
        print("Final best match: \(bestMatch ?? "nil"), score: \(bestScore)")
        
        // 降低阈值，提高识别成功率
        if bestScore > 0.1 { // 进一步降低阈值以提高识别成功率
            print("Returning match: \(bestMatch!)")
            return bestMatch
        }
        
        print("No match found")
        return nil
    }
    
    // 绘制文本
    private func drawText(in image: CIImage, text: String, x: CGFloat, y: CGFloat, width: CGFloat, color: CIColor) -> CIImage {
        // 创建文本图像
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.fontSize = 16
        textLayer.foregroundColor = CGColor(red: 0, green: 1, blue: 0, alpha: 1.0) // 直接使用 CGColor
        textLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        textLayer.alignmentMode = .center
        textLayer.frame = CGRect(x: 0, y: 0, width: width, height: 20)
        
        // 创建一个临时的 CALayer 作为容器
        let containerLayer = CALayer()
        containerLayer.frame = textLayer.frame
        containerLayer.addSublayer(textLayer)
        
        // 渲染文本层到 CGImage
        let textImage = containerLayer.renderedImage()
        
        // 转换为 CIImage
        let textCIImage = CIImage(cgImage: textImage)
        
        // 将文本图像放置在指定位置
        let textWithPosition = textCIImage.transformed(by: CGAffineTransform(translationX: x, y: y))
        
        // 合成到原始图像上
        return textWithPosition.composited(over: image)
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