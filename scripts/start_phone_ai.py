"""Start and verify the authenticated temporary HTTPS development connection."""
from pathlib import Path
import json
import os
import plistlib
import re
import secrets
import signal
import subprocess
import sys
import time
import urllib.request

root = Path(__file__).resolve().parents[1]
envfile = root / 'server/.env'
lines = envfile.read_text().splitlines()
values = dict(line.split('=', 1) for line in lines if '=' in line and not line.startswith('#'))
token = values.get('COOKFLOW_CLIENT_TOKEN') or secrets.token_urlsafe(32)
lines = [line for line in lines if not line.startswith(('COOKFLOW_BIND=', 'COOKFLOW_CLIENT_TOKEN='))]
lines += ['COOKFLOW_BIND=127.0.0.1', 'COOKFLOW_CLIENT_TOKEN=' + token]
envfile.write_text('\n'.join(lines) + '\n'); os.chmod(envfile, 0o600)

def healthy(base):
    try:
        request = urllib.request.Request(base + '/health', headers={'Authorization': 'Bearer ' + token})
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status == 200 and json.load(response).get('status') == 'ready'
    except (OSError, ValueError):
        return False

subprocess.run([sys.executable, str(root / 'scripts/start_ai_server.py')], check=True)
if not healthy('http://127.0.0.1:8765'):
    raise RuntimeError('Mac AI server did not become ready')
pidfile = root / '.build/phone-tunnel.pid'
logfile = root / '.build/phone-tunnel.log'
urlfile = root / '.build/phone-tunnel-url.json'
base = None
old_pid = None
try:
    old_pid = int(pidfile.read_text())
    os.kill(old_pid, 0)
    candidate = json.loads(urlfile.read_text())['url']
    if healthy(candidate): base = candidate
    elif logfile.exists():
        pending = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', logfile.read_text())
        if pending and healthy(pending.group(0)):
            base = pending.group(0)
            urlfile.write_text(json.dumps({'url': base}))
except (OSError, ValueError, KeyError):
    pass
if base is None:
    if old_pid:
        try: os.kill(old_pid, signal.SIGTERM)
        except ProcessLookupError: pass
    with logfile.open('wb') as log:
        process = subprocess.Popen([str(root / '.build/tools/cloudflared'), 'tunnel', '--url', 'http://127.0.0.1:8765', '--protocol', 'http2', '--no-autoupdate'], stdout=log, stderr=log, stdin=subprocess.DEVNULL, start_new_session=True)
    pidfile.write_text(str(process.pid))
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        found = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', logfile.read_text())
        if found:
            candidate = found.group(0)
            if healthy(candidate): base = candidate; break
        if process.poll() is not None: raise RuntimeError('HTTPS tunnel could not start')
        time.sleep(1)
    if not base: raise RuntimeError('HTTPS tunnel health verification failed; app configuration was preserved')
    urlfile.write_text(json.dumps({'url': base}))
from pairing_config import write_pairing
write_pairing(root, base, token)
print('폰 HTTPS AI 연결 확인 완료: ' + base)
