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
# Android SDK設定
ENV ANDROID_SDK_ROOT="/opt/android-sdk"
ENV CMDLINE_TOOLS_DIR="$ANDROID_SDK_ROOT/cmdline-tools/latest"
ENV PATH="$PATH:$CMDLINE_TOOLS_DIR/bin:$ANDROID_SDK_ROOT/platform-tools"

# 1. 必要なパッケージのインストール
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

# Android SDK Command Line Toolsのインストールと配置
# ------------------------------------------------------------------------------------------------
# 1. 最終的な配置先ディレクトリを作成
RUN mkdir -p $CMDLINE_TOOLS_DIR/lib/external/lint-psi/kotlin-compiler \
    && mkdir -p $CMDLINE_TOOLS_DIR/lib/external/lint-psi/intellij-core

# 2. 軽量なファイル群をGitHubからコピー (cmdline-tools/lib, cmdline-tools/bin, etc.)
# 注意: コピー元はリポジトリのルートに対する相対パスです。
# jarファイル（大容量）はリポジトリから除外されている前提。
COPY cmdline-tools/ $CMDLINE_TOOLS_DIR/

# 3. 大容量の JAR ファイルを dl リンクから直接ダウンロードして配置
# kotlin-compiler-mvn.jar (51MB)
RUN wget -q "https://drive.usercontent.google.com/download?id=1rK7CyTrO5UnBiX0WzonjzWxiRoYm508o" -O $CMDLINE_TOOLS_DIR/lib/external/lint-psi/kotlin-compiler/kotlin-compiler-mvn.jar

# intellij-core-mvn.jar (34.7MB)
RUN wget -q "https://drive.usercontent.google.com/download?id=1PGM-KpNLA6YiuANhfX15oAZ06kUjN7or" -O $CMDLINE_TOOLS_DIR/lib/external/lint-psi/intellij-core/intellij-core-mvn.jar
# ------------------------------------------------------------------------------------------------

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
COPY apks/ /apks/  # APKファイルもリポジトリにある場合は、この行を追加

# 4. 統合されたエントリポイントの作成
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# VNCポートとFlaskポートを公開
EXPOSE ${VNC_PORT} ${FLASK_PORT}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
