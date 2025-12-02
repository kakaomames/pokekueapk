# ベースイメージ: Pythonを使用
FROM python:3.10-slim

# 作業ディレクトリの設定
WORKDIR /app

# 依存関係のコピーとインストール
# Renderでの標準的なWeb Service起動には gunicorn を使用します
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt gunicorn

# アプリケーションコードのコピー
COPY flask_app.py .
COPY templates/ templates/

# Renderは環境変数 PORT で指定されたポートを使用します
ARG PORT=8080
ENV PORT=${PORT}

# ポートの公開
EXPOSE ${PORT}

# Gunicornを使ってFlaskアプリを起動
# Web Serviceのエントリポイントとして使用
# --bind 0.0.0.0:${PORT} で、外部からのアクセスを許可
# flask_app:app は、'flask_app.py' の 'app' オブジェクトを指します
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "flask_app:app"]
