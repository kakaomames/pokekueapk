# ベースイメージ: Ubuntu (Android SDKとGUI環境が必要なため)
FROM ubuntu:22.04

# 環境変数
ENV DEBIAN_FRONTEND=noninteractive
# VNC設定
ENV DISPLAY=:1
ENV VNC_PORT=5901
# Python/Flask設定
ENV FLASK_PORT=8080
ENV PORT=${FLASK_PORT}
# Renderのデフォルトポート

# 1. 必要なパッケージのインストール (Java, Android SDK, GUI, VNC, Python)
RUN apt-get update && apt-get install -y \
    wget unzip curl libglu1 libgl1 libsdl1.2debian net-tools \
    openjdk-17-jdk \
    # VNCサーバーとGUI環境
    xfce4 xfce4-goodies tightvncserver \
    # Pythonと依存関係
    python3 python3-pip \
    # ADBとエミュレータの実行に必要
    qemu-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Android SDK Command Line Toolsのインストール
ENV ANDROID_SDK_ROOT="/opt/android-sdk"
ENV PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools"

# 修正部分: 
# URLを 'commandlinetools-linux-latest.zip' に変更し、展開後にフォルダをリネームするロジックを採用。
RUN mkdir -p $ANDROID_SDK_ROOT/cmdline-tools \
    && wget -q **https://dl.google.com/android/repository/commandlinetools-linux-latest.zip** -O android-sdk.zip \
    && unzip -q android-sdk.zip -d $ANDROID_SDK_ROOT/cmdline-tools \
    && rm android-sdk.zip \
    # 展開された "cmdline-tools" フォルダを "latest" にリネーム
    && mv $ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools $ANDROID_SDK_ROOT/cmdline-tools/latest

# ライセンスに同意し、必要なコンポーネントをインストール
# Android 30 (x86_64) をターゲットとする
RUN yes | sdkmanager --licenses \
    && sdkmanager "platform-tools" "emulator" "system-images;android-30;google_apis;x86_64"

# AVDの作成 (Android Virtual Device)
RUN echo "no" | avdmanager create avd -n avd_ipad -k "system-images;android-30;google_apis;x86_64" -d "pixel"

# 2. Python依存関係のインストール (Flask, Gunicorn, WebSocketプロキシ)
WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt gunicorn

# 3. アプリケーションコードのコピー
COPY flask_app.py .
COPY templates/ templates/
# apksファイルを配置するディレクトリを準備
RUN mkdir -p /apks

# 4. 統合されたエントリポイントの作成
# 複数のプロセス (VNCサーバー, エミュレーター, Flask/Gunicorn) を起動・管理するスクリプト
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# VNCポートとFlaskポートを公開
EXPOSE ${VNC_PORT} ${FLASK_PORT}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
