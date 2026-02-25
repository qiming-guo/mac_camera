#!/bin/bash

# 运行CameraCompanionDesktop应用
echo "启动Camera Companion Desktop应用..."

# 检查可执行文件是否存在
if [ -f "CameraCompanionDesktop" ]; then
    # 运行应用
    ./CameraCompanionDesktop
else
    echo "错误: 可执行文件不存在，请先运行 build.sh 编译应用"
    exit 1
fi
