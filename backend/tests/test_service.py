import json
import os
import sys
import threading
import unittest
import urllib.request
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import service
from server import Handler, ThreadingHTTPServer


class ServiceTests(unittest.TestCase):
    def test_transcription_uses_english_and_timestamps(self):
        result = {"text": "Thirty thousand packs.", "segments": [{"start": 1, "end": 3, "text": "Thirty thousand packs."}]}
        with patch("service.provider", return_value=result) as provider:
            actual = service.transcribe(b"test audio", "m4a")
        self.assertEqual(actual["segments"][0]["start"], 1)
        body = provider.call_args.args[1]
        self.assertIn(b'name="language"\r\n\r\nen', body)
        self.assertIn(b"verbose_json", body)
        self.assertIn(b"test audio", body)

    def test_reject_empty_and_unsupported_audio(self):
        for data, extension in [(b"", "m4a"), (b"audio", "exe")]:
            with self.assertRaises(service.ServiceError):
                service.transcribe(data, extension)

    def test_no_speech_is_not_success(self):
        with patch("service.provider", return_value={"text": " ", "segments": []}):
            with self.assertRaises(service.ServiceError):
                service.transcribe(b"silence", "wav")

    def test_invalid_timestamps_are_rejected(self):
        for start, end in [(float("nan"), 2), (1, float("inf")), (-1, 2), (3, 2), (0, 10**20)]:
            with self.subTest(start=start, end=end):
                response = {"text": "Hello", "segments": [{"start": start, "end": end, "text": "Hello"}]}
                with patch("service.provider", return_value=response), self.assertRaises(service.ServiceError):
                    service.transcribe(b"audio", "m4a")

    def test_summary_preserves_unknown_fields_and_flags_invented_quote(self):
        summary = {"overview": "客户询价", "requirements": "", "decisions": "", "open_questions": "",
                   "tasks": [{"title": "发送报价", "owner": "", "due": "", "evidence": "invented quote"}]}
        response = {"choices": [{"message": {"content": json.dumps(summary)}}]}
        with patch("service.provider", return_value=response):
            actual = service.summarize("Please send a quote.")
        self.assertEqual(actual["tasks"][0]["owner"], "")
        self.assertEqual(actual["tasks"][0]["due"], "")
        self.assertIn("待人工核对", actual["tasks"][0]["evidence"])

    def test_malformed_summary_rejected(self):
        for bad in [{}, {"overview": [], "tasks": []}, {"overview": "", "requirements": "", "decisions": "", "open_questions": "", "tasks": [{}]}]:
            with self.assertRaises(service.ServiceError):
                service.validate_summary(bad)

    def test_rate_limit_is_actionable(self):
        with patch.dict(os.environ, {"GROQ_API_KEY": "unit-test-only"}), patch("urllib.request.urlopen", side_effect=urllib.error.HTTPError("https://example.invalid", 429, "limited", {}, None)):
            with self.assertRaises(service.ServiceError) as error:
                service.provider("audio/transcriptions", b"", "application/json")
        self.assertEqual(error.exception.status, 429)


class GatewayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = "http://127.0.0.1:" + str(cls.server.server_port)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def post(self, path, data, token="test-access-token-at-least-24"):
        req = urllib.request.Request(self.url + path, data=data, headers={"Authorization": "Bearer " + token, "X-Audio-Extension": "m4a"})
        try:
            with urllib.request.urlopen(req) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as response:
            with response:
                return response.code, json.load(response)

    @patch.dict(os.environ, {"APP_ACCESS_TOKEN": "test-access-token-at-least-24"})
    def test_unauthorized_never_calls_provider(self):
        with patch("server.transcribe") as provider:
            status, _ = self.post("/transcribe", b"private audio", "wrong")
        self.assertEqual(status, 401)
        provider.assert_not_called()

    @patch.dict(os.environ, {"APP_ACCESS_TOKEN": "test-access-token-at-least-24"})
    def test_audio_route_and_utf8_response(self):
        with patch("server.transcribe", return_value={"text": "hello", "segments": []}) as provider:
            status, body = self.post("/transcribe", b"audio")
        self.assertEqual(status, 200)
        self.assertEqual(body["text"], "hello")
        provider.assert_called_once_with(b"audio", "m4a")

    @patch.dict(os.environ, {"APP_ACCESS_TOKEN": "test-access-token-at-least-24"})
    def test_invalid_json_is_client_error(self):
        self.assertEqual(self.post("/summarize", b"[")[0], 400)
        self.assertEqual(self.post("/summarize", b"[]")[0], 400)

    @patch.dict(os.environ, {"APP_ACCESS_TOKEN": ""})
    def test_unconfigured_server_is_closed(self):
        self.assertEqual(self.post("/transcribe", b"audio")[0], 503)


if __name__ == "__main__":
    unittest.main()
