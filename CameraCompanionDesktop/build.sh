#!/bin/bash

# 编译CameraCompanionDesktop应用
echo "编译Camera Companion Desktop应用..."

# 编译命令
swiftc -o CameraCompanionDesktop CameraCompanionDesktopApp.swift main.swift -framework AppKit -framework Foundation

if [ $? -eq 0 ]; then
    echo "编译成功！"
    chmod +x CameraCompanionDesktop
    echo "可执行文件已创建: CameraCompanionDesktop"
else
    echo "编译失败，请检查错误信息"
    exit 1
fi
