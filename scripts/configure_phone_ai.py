"""Pair this development app with the Mac AI bridge without provider secrets."""
from pathlib import Path
import plistlib
import secrets
import subprocess
import os
root = Path(__file__).resolve().parents[1]
env = root / 'server/.env'
lines = env.read_text().splitlines()
values = dict(line.split('=', 1) for line in lines if '=' in line and not line.startswith('#'))
token = values.get('COOKFLOW_CLIENT_TOKEN') or secrets.token_urlsafe(32)
lines = [line for line in lines if not line.startswith(('COOKFLOW_CLIENT_TOKEN=', 'COOKFLOW_BIND='))]
lines += ['COOKFLOW_CLIENT_TOKEN=' + token, 'COOKFLOW_BIND=0.0.0.0']
env.write_text('\n'.join(lines) + '\n'); os.chmod(env, 0o600)
host = subprocess.check_output(['scutil', '--get', 'LocalHostName'], text=True).strip() + '.local'
from pairing_config import write_pairing
write_pairing(root, 'http://' + host + ':8765', token)
print('폰 AI 자동 연결 설정 완료: ' + host)
