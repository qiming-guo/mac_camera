#!/bin/bash

# 编译所有组件
echo "编译 Camera Companion 应用..."
swiftc -o CameraCompanionApp CameraCompanionApp.swift CameraManager.swift HTTPServer.swift ImageProcessor.swift VideoRecorder.swift

if [ $? -eq 0 ]; then
    echo "编译成功！"
    echo "运行应用: ./run.sh"
else
    echo "编译失败，请检查错误信息"
    exit 1
fi