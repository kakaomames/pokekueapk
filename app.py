# app.py

import os
from flask import Flask
# requestをインポートしてセッションIDを取得できるようにします
from flask_socketio import SocketIO, emit, join_room, leave_room
# Renderでの非同期処理にeventletが推奨されているため、async_mode='eventlet'を設定
from eventlet import monkey_patch

# eventletで非同期処理を可能にするため、標準ライブラリをモンキーパッチします
monkey_patch()

# 隊員、Flaskアプリケーションを起動します！
app = Flask(__name__)

# Secret keyを設定する必要があります。
# 環境変数から取得するか、デフォルト値を設定します。
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'your_strong_secret_key_here_kakaomame')
print(f"SECRET_KEY: {app.config['SECRET_KEY']}")

# SocketIOを初期化します。
# cors_allowed_origins="*" は、VercelやGitHub Pagesからの接続を許可するために設定しています。
socketio = SocketIO(
    app, 
    cors_allowed_origins="*", 
    async_mode='eventlet'
)
print(f"SocketIO async_mode: {socketio.async_mode}")


# 1. 接続時のイベントハンドラ
@socketio.on('connect')
def handle_connect():
    """クライアントがWebSocket接続を確立した時に実行されます。"""
    # ここではPythonのrequestsモジュールは使えないため、flask_socketioの機能を使います
    from flask import request 
    session_id = request.sid
    print(f"クライアントが接続しました！(Session ID: {session_id})")
    
    # 接続したクライアントに直接ウェルカムメッセージを送ります。
    emit('server_response', {'data': f'接続成功！隊員、{session_id}にようこそ！'}, broadcast=False)
    print(f"接続成功メッセージをクライアント {session_id} に送信しました。")


# 2. クライアントからメッセージを受信した時のハンドラ
@socketio.on('client_message')
def handle_client_message(json_data):
    """クライアントから 'client_message' というイベント名でデータを受信した時に実行されます。"""
    print(f"クライアントからのメッセージを受信しました: {json_data}")
    
    # チームチャットのように、受信したメッセージを接続している全員にブロードキャストします。
    message = json_data.get('data', 'No Data')
    emit('server_response', {'data': f'受信メッセージ: "{message}"'}, broadcast=True)
    print("受信メッセージを接続中の全クライアントにブロードキャストしました。")


# メインの実行ブロック
if __name__ == '__main__':
    # Renderでデプロイする場合、GunicornなどのWSGIサーバーを使うのが一般的ですが、
    # 開発環境では socketio.run() で eventletサーバーを使って起動します。
    # host='0.0.0.0' は外部からの接続を許可するために必須です。
    print("WebSocketサーバーを起動します。")
    # print(f"a:{a}") の形式で、各変数の値を表示します
    HOST = '0.0.0.0'
    print(f"HOST:{HOST}")
    PORT = int(os.environ.get('PORT', 5000))
    print(f"PORT:{PORT}")
    
    socketio.run(app, host=HOST, port=PORT, debug=True)
