import os
import docker
import time
from flask import Flask, render_template, request
from gevent.pywsgi import WSGIServer
from geventwebsocket.handler import WebSocketHandler
from geventwebsocket.websocket import WebSocket
import socket

# 環境設定
FLASK_PORT = int(os.environ.get("PORT", 8080))
EMULATOR_IMAGE = "gemini_android_emulator:latest" # エミュレータのDockerイメージ名
CONTAINER_NAME = "android_emulator_container"
VNC_PORT_INTERNAL = 5901 # エミュレータコンテナ内のVNCポート

app = Flask(__name__)
client = docker.from_env()

print(f"client:{client}")
# client:Client(base_url='unix://var/run/docker.sock')

# --- Dockerコンテナ管理関数 ---

def ensure_emulator_running():
    """エミュレータコンテナを起動または再起動し、内部IPアドレスを取得する"""
    try:
        container = client.containers.get(CONTAINER_NAME)
        if container.status != 'running':
            print(f"Container status is {container.status}. Starting...")
            container.start()
            time.sleep(10) # 起動待ち
        
    except docker.errors.NotFound:
        print("Container not found. Creating and starting...")
        # Renderでは、コンテナを分離して起動し、内部ネットワークで通信する必要があります。
        # ここでは、コンテナ名を指定して単に起動のみ行い、IPアドレスを後で取得します。
        # Render Private Serviceとしてデプロイした場合、Web ServiceとPrivate Serviceは
        # サービス名 (CONTAINER_NAME) でアクセス可能になります。
        container = client.containers.run(
            EMULATOR_IMAGE,
            detach=True,
            name=CONTAINER_NAME,
            # Renderではホスト側のポートマッピングは不要（内部ネットワークを使用するため）
            # ただし、ローカルテスト用にポートを公開しても良い
            ports={f'{VNC_PORT_INTERNAL}/tcp': None}, 
            # apksのボリュームマウントはデプロイ環境に合わせて調整
            # 例: ローカルテスト用
            # volumes={os.path.abspath('./apks_data'): {'bind': '/apks', 'mode': 'ro'}}
        )
        time.sleep(15) # 初回起動は時間がかかる
        
    container.reload()
    
    # Renderではサービス名が内部DNS名になるため、ここではダミーのIPを返す
    # 実際のRenderデプロイでは、この値は 'android_emulator_container' になる
    try:
        # ネットワーク設定からIPアドレスを取得（ローカル環境の場合）
        network_settings = container.attrs['NetworkSettings']['Networks']
        # bridgeネットワークのIPを取得（環境による）
        internal_ip = list(network_settings.values())[0]['IPAddress']
    except:
        # Renderデプロイを見据え、コンテナ名をホスト名として使用
        internal_ip = CONTAINER_NAME 
        
    print(f"Emulator Internal IP/Host: {internal_ip}")
    # Emulator Internal IP/Host: android_emulator_container
    return internal_ip

# --- VNCプロキシ機能 (WebSocketハンドラー) ---

@app.route('/websockify', websocket=True)
def websockify():
    """
    ブラウザからのWebSocket接続を受け取り、内部のVNCサーバーにプロキシする。
    """
    if request.environ.get('wsgi.websocket'):
        ws: WebSocket = request.environ['wsgi.websocket']
        
        # 内部エミュレータのホスト/ポートを取得
        target_host = ensure_emulator_running()
        target_port = VNC_PORT_INTERNAL
        
        # 内部VNCサーバーへのTCP接続
        try:
            print(f"Attempting to connect to VNC server: {target_host}:{target_port}")
            vnc_socket = socket.create_connection((target_host, target_port), timeout=10)
            print("Successfully connected to VNC server.")
            
            # データの双方向中継を開始
            # geventを使って非同期で処理
            from gevent import spawn
            
            # VNC -> WebSocket (エミュレータ -> iPad)
            def vnc_to_ws():
                try:
                    while True:
                        data = vnc_socket.recv(4096)
                        if not data:
                            break
                        ws.send(data)
                except Exception as e:
                    print(f"VNC->WS error: {e}")
                finally:
                    print("VNC->WS ended.")

            # WebSocket -> VNC (iPad -> エミュレータ)
            def ws_to_vnc():
                try:
                    while True:
                        data = ws.receive()
                        if data is None:
                            break
                        # WebSocketはテキストとバイナリを扱うが、VNCはバイナリ
                        if isinstance(data, str):
                            data = data.encode('utf-8') 
                        vnc_socket.sendall(data)
                except Exception as e:
                    print(f"WS->VNC error: {e}")
                finally:
                    print("WS->VNC ended.")

            # 両方向の通信を並列実行し、どちらかが終了するのを待つ
            g1 = spawn(vnc_to_ws)
            g2 = spawn(ws_to_vnc)
            g1.join()
            g2.join()

        except ConnectionRefusedError:
            error_msg = f"VNC connection refused to {target_host}:{target_port}. Is the emulator running?"
            print(error_msg)
            ws.send(error_msg.encode('utf-8'))
        except socket.timeout:
            error_msg = f"VNC connection timed out to {target_host}:{target_port}."
            print(error_msg)
            ws.send(error_msg.encode('utf-8'))
        except Exception as e:
            print(f"Proxy error: {e}")
            
        finally:
            # 接続を閉じる
            if 'vnc_socket' in locals():
                vnc_socket.close()
            print("WebSocket session ended.")

    return "" # ルーティングの戻り値は必須

# --- 標準のFlaskルーティング ---

@app.route('/')
def index():
    """VNCクライアントのページを表示"""
    # エミュレータが起動していることを確認（プロキシが自動的に実行）
    emulator_host = ensure_emulator_running()
    
    # index.htmlに渡す情報
    # noVNCクライアントは自身のホスト/ポートの /websockify パスに接続します
    vnc_params = {
        'host': request.host.split(':')[0], # Renderのホスト名
        'port': FLASK_PORT, # Renderのポート (8080)
        'path': 'websockify', # プロキシルーティング
        'emulator_host': emulator_host # デバッグ用
    }
    print(f"vnc_params:{vnc_params}")
    # vnc_params:{'host': '0.0.0.0', 'port': 8080, 'path': 'websockify', 'emulator_host': 'android_emulator_container'}

    return render_template('index.html', **vnc_params)

# ローカルでの実行用（RenderではGunicornを使用）
if __name__ == '__main__':
    # 開発環境でgeventを使ってWebSocketハンドラーを設定
    print(f"Starting server on port {FLASK_PORT} with WebSocket support...")
    http_server = WSGIServer(('0.0.0.0', FLASK_PORT), app, handler_class=WebSocketHandler)
    http_server.serve_forever()
