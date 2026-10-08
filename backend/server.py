"""Loopback-only development gateway. Put production auth/TLS in front before release."""
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from service import MAX_AUDIO, ServiceError, transcribe, summarize


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log request bodies, tokens or customer content.

    def reply(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(200 if self.path == "/health" else 404,
                   {"status": "ok"} if self.path == "/health" else {"error": "Not found"})

    def do_POST(self):
        self.connection.settimeout(30)
        token = os.environ.get("APP_ACCESS_TOKEN", "")
        if len(token) < 24:
            return self.reply(503, {"error": "服务端尚未配置访问凭据。"})
        if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + token):
            return self.reply(401, {"error": "访问令牌无效，请检查设置。"})
        try:
            if self.path not in {"/transcribe", "/summarize"}:
                raise ServiceError("Not found", 404)
            size = int(self.headers.get("Content-Length", "0"))
            limit = MAX_AUDIO if self.path == "/transcribe" else 600_000
            if size <= 0 or size > limit:
                raise ServiceError("请求为空或文件过大。", 413)
            data = self.rfile.read(size)
            if len(data) != size:
                raise ServiceError("上传未完成，请重试。")
            if self.path == "/transcribe":
                result = transcribe(data, self.headers.get("X-Audio-Extension", "").lower())
            else:
                body = json.loads(data)
                if not isinstance(body, dict):
                    raise ServiceError("请求格式无效。")
                result = summarize(body.get("text"))
            self.reply(200, result)
        except ServiceError as exc:
            self.reply(exc.status, {"error": str(exc)})
        except (ValueError, UnicodeError, TimeoutError):
            self.reply(400, {"error": "请求格式无效或上传超时。"})
        except Exception:
            self.reply(500, {"error": "处理失败，请稍后重试。"})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 8787), Handler)
    print("Development gateway: http://127.0.0.1:8787 (not a production deployment)")
    server.serve_forever()
