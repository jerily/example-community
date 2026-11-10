"""Real HTTP, shared mounts, auth, persistence and CSRF. No Docker required."""
import html
import http.cookiejar
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PASSWORD = "long community test password"

def main():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    base = f"http://localhost:{port}"
    jar = http.cookiejar.CookieJar()
    client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    def fetch(path, fields=None, status=200):
        data = None if fields is None else urllib.parse.urlencode(fields).encode()
        try:
            response = client.open(base + path, data=data, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        body = response.read().decode()
        assert response.status == status, (path, response.status, body)
        return body
    def csrf(body):
        return html.unescape(re.search(r'name="csrf" value="([^"]+)"', body)[1])
    def code(body):
        return re.search(r'id="local-code">([^<]+)', body)[1]
    with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryFile(mode="w+") as log:
        env = dict(os.environ, PROJECT_HOME=folder, ENV="LOCAL")
        def start():
            proc = subprocess.Popen([sys.argv[1], str(ROOT / "main.tcl"), "--port", str(port)], env=env, cwd=folder, stdout=log, stderr=log)
            for _ in range(100):
                if proc.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                try:
                    fetch("/")
                    return proc
                except OSError:
                    time.sleep(.05)
            proc.terminate()
            raise AssertionError("server did not start")
        proc = start()
        try:
            assert "A little space to grow." in fetch("/")
            for path, text in [("/forum", "Community discussions"), ("/wiki/community-handbook", "Community handbook"), ("/blog", "A place to build together")]:
                body = fetch(path)
                assert "Juniper Yard" in body and text in body, (path, body)
            for kind in ("wiki", "blog"):
                assert f'/{kind}/_new' not in fetch(f'/{kind}')
            assert '/wiki/_edit' not in fetch('/wiki/community-handbook')
            assert '/blog/_edit' not in fetch('/blog/2026-11-10-a-place-to-build-together')
            fetch("/wiki/_new", status=403)
            body = fetch("/user/register")
            body = fetch("/user/register", dict(email="member@example.com", password=PASSWORD, csrf=csrf(body)))
            body = fetch("/user/verify", dict(code=code(body), csrf=csrf(body)))
            body = fetch("/user/login", dict(email="member@example.com", password=PASSWORD, csrf=csrf(body)))
            assert "Signed in as member@example.com" in body
            for kind in ("wiki", "blog"):
                assert f'/{kind}/_new' in fetch(f'/{kind}')
            assert '/wiki/_edit' in fetch('/wiki/community-handbook')
            assert '/blog/_edit' in fetch('/blog/2026-11-10-a-place-to-build-together')
            assert '/wiki/_edit/a-little-space-to-grow' in fetch('/')
            body = fetch('/wiki/_edit/a-little-space-to-grow')
            revision = re.search(r'name="revision" value="([^"\s]+)"', body)[1]
            markdown = html.unescape(re.search(r'<textarea[^>]*name="markdown"[^>]*>(.*?)</textarea>', body, re.S)[1])
            fetch('/wiki/_edit/a-little-space-to-grow', dict(title='A little space to grow.', markdown=markdown+'\n\nA member improved our home page.\n<script>unsafe()</script>', revision=revision, csrf=csrf(body)))
            home = fetch('/')
            assert 'A member improved our home page.' in home and '<script>unsafe()' not in home
            assert any('.' in cookie.value for cookie in jar), 'session cookie must be signed'
            body = fetch("/forum/new")
            body = fetch("/forum/new", dict(title="First discussion", body="Hello <script>alert(1)</script>", csrf=csrf(body)))
            assert "First discussion" in body and "&lt;script&gt;" in body and "<script>alert" not in body
            for kind in ("wiki", "blog"):
                body = fetch(f"/{kind}/_new")
                fields = dict(title="Community HTTP note", markdown="A persistent community note.", csrf=csrf(body))
                if kind == "blog": fields["published_at"] = "2026-11-10"
                assert "A persistent community note" in fetch(f"/{kind}/_new", fields)
            body = fetch("/user")
            token = csrf(body)
            fetch("/user/logout", dict(csrf="wrong"), status=403)
            fetch("/user/logout", dict(csrf=token))
            fetch("/forum/new", dict(title="Denied", body="No access", csrf=token), status=401)
            assert '/wiki/_edit' not in fetch('/')
            assert '/wiki/_new' not in fetch('/wiki')
            assert '/blog/_new' not in fetch('/blog')
            proc.send_signal(signal.SIGTERM)
            proc.wait(timeout=5)
            proc = start()
            assert "First discussion" in fetch("/forum")
            assert "A member improved our home page." in fetch("/")
            body = fetch("/user/login")
            body = fetch("/user/login", dict(email="member@example.com", password=PASSWORD, csrf=csrf(body)))
            assert "Signed in as member@example.com" in body
            body = fetch("/user/forgot", dict(email="member@example.com", csrf=csrf(body)))
            body = fetch("/user/reset", dict(code=code(body), password=PASSWORD + " updated", csrf=csrf(body)))
            assert "Password changed" in body
            fetch("/user/login", dict(email="member@example.com", password=PASSWORD, csrf=csrf(body)), status=401)
            body = fetch("/user/login", dict(email="member@example.com", password=PASSWORD + " updated", csrf=csrf(body)))
            assert "Signed in as" in body
            print("HTTP checks passed: all mounts, signed cookies, login-aware controls, wiki-backed home, CSRF, reset and restart persistence.")
        finally:
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                proc.wait(timeout=5)
            if sys.exc_info()[0]:
                log.seek(0)
                print(log.read(), file=sys.stderr)

if __name__ == "__main__": main()
