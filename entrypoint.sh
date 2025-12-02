#!/bin/bash
set -m # ジョブ制御を有効にする

# 1. VNCサーバーの起動
echo "Starting VNC server on display :1"
tightvncserver :1 -geometry 1280x800 -depth 24
export DISPLAY=:1

# 2. Android Emulatorの起動 (バックグラウンド実行)
echo "Starting Android Emulator 'avd_ipad'"
# -no-windowでGUIなし、-gpu swiftshader_indirectでソフトウェアレンダリング
# -qemu -vnc 127.0.0.1:${VNC_PORT} はVNC経由でのアクセスを試みるが、
# tightvncserverと競合するため、ここでは通常のヘッドレス起動を使用し、
# tightvncserverのX Server内でエミュレーターの画面をレンダリングさせる。
emulator -avd avd_ipad -no-window -gpu swiftshader_indirect &

# 3. エミュレーターが完全に起動するのを待つ (adb shell が動作するまで)
/opt/android-sdk/platform-tools/adb wait-for-device

# 4. apksのインストール (デプロイ時に /apks/app.apks が存在する場合)
if [ -f "/apks/app.apks" ]; then
    echo "Installing apks file..."
    /opt/android-sdk/platform-tools/adb install /apks/app.apks
fi

# 5. Gunicorn (Flask Web Service + VNCプロキシ) の起動
# これをフォアグラウンドで実行し、メインプロセスとする
echo "Starting Gunicorn (Flask Web Service + VNC Proxy)"
# VNCプロキシはコンテナ内部のVNCサーバー(127.0.0.1:5901)に接続する
# tightvncserver が X Server の画面を出力している
exec gunicorn -k geventwebsocket -b 0.0.0.0:${FLASK_PORT} flask_app:app
