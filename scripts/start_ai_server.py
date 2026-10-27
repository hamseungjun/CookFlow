"""Start the local CookFlow bridge detached from the development terminal."""
from pathlib import Path
import subprocess
import sys
import urllib.request

root = Path(__file__).resolve().parent.parent
values = dict(line.split('=', 1) for line in (root / 'server/.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
headers = {'Authorization': 'Bearer ' + values['COOKFLOW_CLIENT_TOKEN']} if values.get('COOKFLOW_CLIENT_TOKEN') else {}
try:
    with urllib.request.urlopen(urllib.request.Request('http://localhost:8765/health', headers=headers), timeout=2) as response:
        print('CookFlow AI 서버가 이미 실행 중입니다.')
        raise SystemExit(0)
except OSError:
    pass
(root / '.build').mkdir(exist_ok=True)
with (root / '.build/ai-server.log').open('ab') as log:
    process = subprocess.Popen([sys.executable, str(root / 'server/app.py')], cwd=root, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
(root / '.build/ai-server.pid').write_text(str(process.pid))
print('CookFlow AI 서버를 실행했습니다. localhost:8765')
