#!/bin/bash

# 检查应用是否存在
if [ -f "./CameraCompanionApp" ]; then
    echo "启动 Camera Companion 应用..."
    ./CameraCompanionApp
else
    echo "应用不存在，请先编译"
    echo "执行: ./build.sh"
    exit 1
fi