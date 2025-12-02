import os
import time
from flask import Flask, render_template, request
# WebSocket通信と非同期処理に gevent/gevent-websocket を使用
from gevent.pywsgi import WSGIServer
from geventwebsocket.handler import WebSocketHandler
from geventwebsocket.websocket import WebSocket
import socket
from gevent import spawn

# --- 環境設定 ---
# Renderによって自動的に環境変数 PORT が設定される
FLASK_PORT = int(os.environ.get("PORT", 8080))

# VNCサーバーは、この単一コンテナ内のローカルホストで動作する
VNC_HOST_INTERNAL = "127.0.0.1" 
VNC_PORT_INTERNAL = 5901 

app = Flask(__name__)

# --- VNCプロキシ機能 (WebSocketハンドラー) ---

@app.route('/websockify', websocket=True)
def websockify():
    """
    ブラウザからのWebSocket接続を受け取り、ローカルのVNCサーバーにTCP接続としてプロキシする。
    """
    # request.environ['wsgi.websocket'] が存在する場合、WebSocket接続である
    if request.environ.get('wsgi.websocket'):
        ws: WebSocket = request.environ['wsgi.websocket']
        
        target_host = VNC_HOST_INTERNAL # 127.0.0.1
        target_port = VNC_PORT_INTERNAL # 5901
        
        vnc_socket = None
        
        try:
            print(f"Attempting to connect to internal VNC: {target_host}:{target_port}")
            # 内部VNCサーバーへのTCP接続を確立
            vnc_socket = socket.create_connection((target_host, target_port), timeout=10)
            print("Successfully connected to VNC server.")
            
            # データの双方向中継を開始

            # VNC -> WebSocket (エミュレータ -> iPad)
            def vnc_to_ws():
                try:
                    while True:
                        # VNCサーバーからデータを受信
                        data = vnc_socket.recv(4096)
                        if not data:
                            print("VNC server closed connection.")
                            break
                        # WebSocket経由でブラウザへ送信
                        ws.send(data)
                except Exception as e:
                    # WebSocket切断、VNCソケットエラーなど
                    print(f"VNC->WS error: {e}")
                finally:
                    print("VNC->WS ended.")

            # WebSocket -> VNC (iPad -> エミュレータ)
            def ws_to_vnc():
                try:
                    while True:
                        # ブラウザからWebSocket経由でデータを受信
                        data = ws.receive()
                        if data is None:
                            print("WebSocket client closed connection.")
                            break
                        # VNCソケット経由でVNCサーバーへ送信
                        # VNCはバイナリプロトコルのため、データが文字列ならエンコードする
                        if isinstance(data, str):
                            data = data.encode('utf-8') 
                        vnc_socket.sendall(data)
                except Exception as e:
                    # WebSocket切断、VNCソケットエラーなど
                    print(f"WS->VNC error: {e}")
                finally:
                    print("WS->VNC ended.")

            # 両方向の通信をgeventで並列実行し、どちらかの通信が終了するのを待つ
            g1 = spawn(vnc_to_ws)
            g2 = spawn(ws_to_vnc)
            g1.join()
            g2.join()

        except socket.timeout:
            error_msg = f"VNC connection timed out to {target_host}:{target_port}."
            print(error_msg)
            if not ws.closed:
                ws.send(error_msg.encode('utf-8'))
        except ConnectionRefusedError:
            error_msg = f"VNC connection refused to {target_host}:{target_port}. Is the emulator fully initialized?"
            print(error_msg)
            if not ws.closed:
                ws.send(error_msg.encode('utf-8'))
        except Exception as e:
            print(f"Proxy critical error: {e}")
            if not ws.closed:
                ws.send(f"Critical error: {e}".encode('utf-8'))
            
        finally:
            # 接続を閉じる
            if vnc_socket:
                vnc_socket.close()
            print("WebSocket session completed and VNC socket closed.")

    return "" # Flask/Gunicornのルーティングの戻り値は必須

# --- 標準のFlaskルーティング ---

@app.route('/')
def index():
    """VNCクライアントのページを表示"""
    vnc_params = {
        # Renderのホスト名 (例: your-service.onrender.com)
        'host': request.host.split(':')[0],
        # Renderが公開しているWeb Serviceのポート
        'port': FLASK_PORT,
        # VNCプロキシ機能へのパス
        'path': 'websockify'
    }
    print(f"vnc_params:{vnc_params}")

    # templates/index.html をレンダリング
    return render_template('index.html', **vnc_params)

# --- 起動設定 ---
# Renderでは Gunicorn がこのアプリをロードするため、このブロックは基本的に不要だが、
# ローカルでテストする際に gevent を使って起動するために残しておく。
if __name__ == '__main__':
    print(f"Starting local server on port {FLASK_PORT} with WebSocket support...")
    # geventのWSGIServerとWebSocketHandlerを使用して起動
    http_server = WSGIServer(('0.0.0.0', FLASK_PORT), app, handler_class=WebSocketHandler)
    http_server.serve_forever()
