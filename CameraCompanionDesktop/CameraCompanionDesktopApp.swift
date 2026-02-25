import AppKit
import Foundation
class AppDelegate: NSObject, NSApplicationDelegate {
    // 菜单栏相关
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    
    // 服务状态
    private var isServiceRunning = false
    private var process: Process?
    
    // 录像状态
    private var isRecording = false
    
    // API客户端
    private let apiClient = APIClient(baseURL: "http://localhost:8999")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        fputs("DEBUG: applicationDidFinishLaunching called\n", stderr)
        // 设置应用激活策略为accessory模式（专为菜单栏应用设计）
        NSApplication.shared.setActivationPolicy(.accessory)
        setupMenuBar()
        fputs("DEBUG: setupMenuBar completed\n", stderr)
        // 激活应用
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    // 设置菜单栏
    private func setupMenuBar() {
        fputs("DEBUG: setupMenuBar started\n", stderr)
        // 创建状态栏项目
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // 设置图标 - 使用白色底的相机图标
        if let button = statusItem.button {
            // 使用系统相机图标
            let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Camera Companion")
            image?.isTemplate = false // 禁用模板模式，使用原始颜色
            button.image = image
            button.title = "" // 清除emoji
        }
        
        // 创建菜单
        menu = NSMenu()
        
        // 服务控制 - 合并为单个按钮
        let serviceItem = NSMenuItem(title: "启动服务", action: #selector(toggleService), keyEquivalent: "")
        
        // 功能菜单项
        let captureItem = NSMenuItem(title: "拍照", action: #selector(capturePhoto), keyEquivalent: "")
        captureItem.isEnabled = false
        
        // 录像控制 - 合并为单个按钮
        let recordItem = NSMenuItem(title: "开始录像", action: #selector(toggleRecording), keyEquivalent: "")
        recordItem.isEnabled = false
        
        // 查看功能
        let viewStreamItem = NSMenuItem(title: "查看视频流", action: #selector(viewStream), keyEquivalent: "")
        viewStreamItem.isEnabled = false
        
        // 分隔线
        menu.addItem(NSMenuItem.separator())
        
        // 退出
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        
        // 添加菜单项
        menu.addItem(serviceItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(captureItem)
        menu.addItem(recordItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(viewStreamItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        
        // 必须将菜单赋值给 statusItem
        statusItem.menu = menu
        fputs("DEBUG: menu assigned to statusItem\n", stderr)
    }
    
    // 启动服务
    @objc private func startService() {
        guard !isServiceRunning else { return }
        
        // 获取当前目录的绝对路径
        let currentPath = FileManager.default.currentDirectoryPath
        // 构建CameraCompanionApp的绝对路径
        let binaryPath = "\(currentPath)/../CameraCompanionApp"
        let absoluteBinaryPath = URL(fileURLWithPath: binaryPath).standardized.path
        
        print("启动服务，路径：\(absoluteBinaryPath)")
        
        // 检查文件是否存在
        if !FileManager.default.fileExists(atPath: absoluteBinaryPath) {
            showNotification(title: "启动失败", subtitle: "Camera Companion二进制文件不存在")
            print("Error: CameraCompanionApp not found at \(absoluteBinaryPath)")
            return
        }
        
        // 检查文件是否可执行
        if !FileManager.default.isExecutableFile(atPath: absoluteBinaryPath) {
            showNotification(title: "启动失败", subtitle: "Camera Companion文件不可执行")
            print("Error: CameraCompanionApp is not executable")
            return
        }
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: absoluteBinaryPath)
        process?.standardOutput = FileHandle.standardOutput
        process?.standardError = FileHandle.standardError
        
        do {
            try process?.run()
            // 等待一下确保服务启动
            Thread.sleep(forTimeInterval: 1.0)
            isServiceRunning = true
            updateMenuState()
            showNotification(title: "服务启动", subtitle: "Camera Companion服务已启动")
            print("Service started successfully")
        } catch {
            showNotification(title: "启动失败", subtitle: "无法启动Camera Companion服务: \(error.localizedDescription)")
            print("Error starting service: \(error)")
        }
    }
    
    // 停止服务
    @objc private func stopService() {
        guard isServiceRunning else { return }
        
        process?.terminate()
        process = nil
        isServiceRunning = false
        updateMenuState()
        showNotification(title: "服务停止", subtitle: "Camera Companion服务已停止")
    }
    
    // 切换服务状态
    @objc private func toggleService() {
        if isServiceRunning {
            stopService()
        } else {
            startService()
        }
    }
    
    // 切换录像状态
    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    // 拍照
    @objc private func capturePhoto() {
        apiClient.capturePhoto { success, error in
            if success {
                self.showNotification(title: "拍照成功", subtitle: "照片已保存")
            } else {
                self.showNotification(title: "拍照失败", subtitle: error ?? "未知错误")
            }
        }
    }
    
    // 开始录像
    @objc private func startRecording() {
        apiClient.startRecording { success, error in
            if success {
                self.isRecording = true
                self.updateMenuState()
                self.showNotification(title: "录像开始", subtitle: "开始录制视频")
            } else {
                self.showNotification(title: "录像失败", subtitle: error ?? "未知错误")
            }
        }
    }
    
    // 停止录像
    @objc private func stopRecording() {
        apiClient.stopRecording { success, error in
            if success {
                self.isRecording = false
                self.updateMenuState()
                self.showNotification(title: "录像停止", subtitle: "视频已保存")
            } else {
                self.showNotification(title: "停止失败", subtitle: error ?? "未知错误")
            }
        }
    }
    
    // 查看视频流
    @objc private func viewStream() {
        if let url = URL(string: "http://localhost:8999/stream") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // 退出应用
    @objc private func quit() {
        stopService()
        NSApplication.shared.terminate(nil)
    }
    
    // 更新菜单状态
    private func updateMenuState() {
        guard let menu = statusItem.menu else { return }
        
        for item in menu.items {
            switch item.title {
            case "启动服务", "停止服务":
                // 更新服务按钮的标题和状态
                if isServiceRunning {
                    item.title = "停止服务"
                } else {
                    item.title = "启动服务"
                }
                item.isEnabled = true
            case "开始录像", "停止录像":
                // 更新录像按钮的标题和状态
                if isRecording {
                    item.title = "停止录像"
                } else {
                    item.title = "开始录像"
                }
                item.isEnabled = isServiceRunning
            case "拍照", "查看视频流":
                item.isEnabled = isServiceRunning
            default:
                break
            }
        }
    }
    
    // 显示通知
    private func showNotification(title: String, subtitle: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// API客户端
class APIClient {
    private let baseURL: String
    
    init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    // 拍照
    func capturePhoto(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/record") else {
            completion(false, "无效的URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(false, "服务器响应错误")
                return
            }
            
            completion(true, nil)
        }
        
        task.resume()
    }
    
    // 开始录像
    func startRecording(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/startRecord") else {
            completion(false, "无效的URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(false, "服务器响应错误")
                return
            }
            
            completion(true, nil)
        }
        
        task.resume()
    }
    
    // 停止录像
    func stopRecording(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/stopRecord") else {
            completion(false, "无效的URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(false, "服务器响应错误")
                return
            }
            
            completion(true, nil)
        }
        
        task.resume()
    }
}
