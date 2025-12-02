#!/bin/bash
# entrypoint.sh

# 1. VNCサーバーの起動
echo "Starting VNC server on display $DISPLAY"
# 修正点: USER 環境変数を設定
export USER=root
# VNCサーバーをバックグラウンドで起動
/usr/bin/tightvncserver -geometry 1280x800 -depth 24 $DISPLAY &
# VNCサーバーが完全に起動するまで少し待機
sleep 3

# Android SDKの環境変数を設定（念のため再確認）
# Dockerfileで設定済みだが、実行環境によっては引き継がれない場合があるため。
export ANDROID_SDK_ROOT="/opt/android-sdk"
export CMDLINE_TOOLS_DIR="$ANDROID_SDK_ROOT/cmdline-tools/latest"
export PATH="$PATH:$CMDLINE_TOOLS_DIR/bin:$ANDROID_SDK_ROOT/platform-tools"

# 2. エミュレーターの起動
echo "Starting Android Emulator 'avd_ipad'"

# 修正点: LD_LIBRARY_PATHを設定し、emulatorへのフルパスを指定
# エミュレータ実行に必要な共有ライブラリのパスを明示的に設定
export LD_LIBRARY_PATH="$ANDROID_SDK_ROOT/emulator/lib64:$ANDROID_SDK_ROOT/emulator/lib64/qt/lib:$LD_LIBRARY_PATH"

# エミュレータをGUIなし、VNCと同じディスプレイで起動 (OpenGLを有効化)
# **注意: Render環境ではハードウェアアクセラレーションは使えないため、ソフトウェアレンダリングを使用**
# -no-window: GUIウィンドウを表示しない (VNCのX Serverが使用される)
# -gpu swiftshader_indirect: ソフトウェアレンダリングを使用
# -camera-back none: カメラを無効化
/opt/android-sdk/emulator/emulator -avd avd_ipad -no-audio -no-window -gpu swiftshader_indirect -camera-back none -qemu -vnc 127.0.0.1:1 -D -r &

# エミュレーターが完全に起動するまで待機
echo "Waiting for Android Emulator to boot..."
/opt/android-sdk/platform-tools/adb wait-for-device

# 3. アプリケーションのインストール (APKs)
echo "Installing app.apks..."
/opt/android-sdk/platform-tools/adb install /apks/app.apks

# 4. Flask Web Service (Gunicorn) の起動
echo "Starting Gunicorn (Flask Web Service + VNC Proxy) on port $FLASK_PORT"
# 0.0.0.0:8080 (FLASK_PORT) で起動し、Renderからのトラフィックを受け付ける
gunicorn --bind 0.0.0.0:$FLASK_PORT "flask_app:app" -k geventwebsocket.gunicorn.workers.GeventWebSocketWorker
