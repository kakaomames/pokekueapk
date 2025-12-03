#!/bin/bash
# entrypoint.sh

# 1. VNCサーバーの初期設定 (パスワード設定)
echo "Setting VNC password file..."
# VNCパスワードファイルを作成 (パスワードは "password" や "123456" など短すぎないもの)
# ここではダミーのパスワードを設定し、プロンプトを回避
mkdir -p /root/.vnc
echo "123456\n123456\nn" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# VNCサーバーの起動
echo "Starting VNC server on display $DISPLAY"
export USER=root
# VNCサーバーをバックグラウンドで起動
/usr/bin/tightvncserver -geometry 1280x800 -depth 24 $DISPLAY -rfbport 5901 &
# VNCサーバーが完全に起動するまで少し待機
sleep 3

# Android SDKの環境変数を設定（念のため再確認）
export ANDROID_SDK_ROOT="/opt/android-sdk"
export CMDLINE_TOOLS_DIR="$ANDROID_SDK_ROOT/cmdline-tools/latest"
export PATH="$PATH:$CMDLINE_TOOLS_DIR/bin:$ANDROID_SDK_ROOT/platform-tools"

# 2. エミュレーターの起動 (ARM/ソフトウェアエミュレーション用)
echo "Starting Android Emulator 'avd_ipad'"
# エミュレータ実行に必要な共有ライブラリのパスを明示的に設定
export LD_LIBRARY_PATH="$ANDROID_SDK_ROOT/emulator/lib64:$ANDROID_SDK_ROOT/emulator/lib64/qt/lib:$LD_LIBRARY_PATH"

# エミュレータをGUIなし、VNCと同じディスプレイで起動 (ARMイメージはKVM不要)
# -no-window: GUIウィンドウを表示しない (VNCのX Serverが使用される)
# -gpu swiftshader_indirect: ソフトウェアレンダリングを使用 (必須)
# -no-snapshot-load: スナップショット読み込みを無効化し、クリーンな起動を強制
/opt/android-sdk/emulator/emulator -avd avd_ipad -no-audio -no-window -gpu swiftshader_indirect -no-snapshot-load -camera-back none &

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
