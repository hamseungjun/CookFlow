"""Keep the free HTTPS bridge alive; retain its current URL until reconnecting."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

runtime = Path(sys.argv[1])
values = dict(line.split('=', 1) for line in (runtime / '.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
statefile = runtime / 'connection.json'
logfile = runtime / 'tunnel.log'

def healthy(url):
    try:
        req = urllib.request.Request(url + '/health', headers={'Authorization': 'Bearer ' + values['COOKFLOW_CLIENT_TOKEN']})
        with urllib.request.urlopen(req, timeout=6) as response:
            return response.status == 200 and json.load(response).get('status') == 'ready'
    except Exception: return False

def save(pid, url):
    statefile.write_text(json.dumps({'pid': pid, 'url': url}))
    (runtime / 'AI 서버 주소.txt').write_text(url + '\n')

def alive(pid):
    try:
        os.kill(pid, 0)
        # A defunct cloudflared still answers kill(pid, 0), but has no tunnel.
        status = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True).stdout.strip()
        return bool(status) and not status.startswith('Z')
    except OSError: return False

while True:
    try: state = json.loads(statefile.read_text())
    except Exception: state = {}
    pid, url = state.get('pid'), state.get('url')
    if pid and url and alive(pid):
        misses = 0
        while alive(pid):
            time.sleep(20)
            misses = 0 if healthy(url) else misses + 1
            if misses >= 4:
                command = subprocess.run(['ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
                if 'cloudflared' in command:
                    try: os.kill(pid, 15)
                    except OSError: pass
                break
    if not healthy('http://127.0.0.1:8765'):
        time.sleep(5); continue
    with logfile.open('wb') as log:
        child = subprocess.Popen([str(runtime / 'cloudflared'), 'tunnel', '--url', 'http://127.0.0.1:8765', '--protocol', 'http2', '--no-autoupdate'], stdin=subprocess.DEVNULL,stdout=log,stderr=log)
    deadline = time.monotonic() + 180
    url = None
    while child.poll() is None and time.monotonic() < deadline:
        match = re.search(r'https://[a-z0-9-]+\.trycloudflare\.com', logfile.read_text(errors='replace'))
        if match and healthy(match.group(0)):
            url = match.group(0); save(child.pid, url); break
        time.sleep(3)
    if not url:
        child.terminate(); child.wait(timeout=10); time.sleep(10)
