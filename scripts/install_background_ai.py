"""Install user-level AI services without paid hosting or modifying system settings."""
from pathlib import Path
import json
import os
import plistlib
import shutil
import sqlite3
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
runtime = Path.home() / 'Library/Application Support/CookFlowServer'
runtime.mkdir(parents=True, exist_ok=True); os.chmod(runtime, 0o700)
for source, name in [(root/'server/app.py','app.py'), (root/'server/preparation_images.py','preparation_images.py'), (root/'server/speech_gate.py','speech_gate.py'), (root/'server/recipe_rules.json','recipe_rules.json'), (root/'server/.env','.env'), (root/'scripts/remote_ai_supervisor.py','remote_ai_supervisor.py'),(root/'.build/tools/cloudflared','cloudflared')]:
    shutil.copy2(source,runtime/name)
shutil.copytree(root/'server/vendor',runtime/'vendor',dirs_exist_ok=True)
os.chmod(runtime/'.env',0o600); os.chmod(runtime/'cloudflared',0o700)
source_db=root/'server/data/preparation-images.sqlite3'
if source_db.exists() and not (runtime/'data/preparation-images.sqlite3').exists():
    (runtime/'data').mkdir(exist_ok=True)
    with sqlite3.connect(source_db) as source, sqlite3.connect(runtime/'data/preparation-images.sqlite3') as dest: source.backup(dest)
if not (runtime/'connection.json').exists():
    url=json.loads((root/'.build/phone-tunnel-url.json').read_text())['url']
    pid=int((root/'.build/phone-tunnel.pid').read_text())
    (runtime/'connection.json').write_text(json.dumps({'pid':pid,'url':url}))
    (runtime/'AI 서버 주소.txt').write_text(url+'\n')
launchdir=Path.home()/'Library/LaunchAgents'; launchdir.mkdir(exist_ok=True)
uid=os.getuid()
services={
 'com.cookflow.ai': [sys.executable,str(runtime/'app.py')],
 'com.cookflow.remote': [sys.executable,str(runtime/'remote_ai_supervisor.py'),str(runtime)],
 'com.cookflow.awake': ['/usr/bin/caffeinate','-i','-s'],
}
# Updating the API must not tear down its temporary HTTPS tunnel: doing so
# rotates the address already embedded in installed phone builds.
retained = set()
for label in services:
    running = subprocess.run(['launchctl', 'print', f'gui/{uid}/{label}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if label != 'com.cookflow.ai' and running:
        retained.add(label)
    else:
        subprocess.run(['launchctl','bootout',f'gui/{uid}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
# Replace only the known development server process; never kill arbitrary port owners.
try:
    old=int((root/'.build/ai-server.pid').read_text())
    command=subprocess.run(['ps','-p',str(old),'-o','command='],capture_output=True,text=True).stdout
    if str(root/'server/app.py') in command: os.kill(old,15)
except (OSError,ValueError): pass
for label,args in services.items():
    plist={'Label':label,'ProgramArguments':args,'WorkingDirectory':str(runtime),'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':10,'StandardOutPath':str(runtime/(label+'.log')),'StandardErrorPath':str(runtime/(label+'.error.log'))}
    if label=='com.cookflow.ai': plist['EnvironmentVariables']={'COOKFLOW_BIND':'127.0.0.1','COOKFLOW_IMAGE_DB':str(runtime/'data/preparation-images.sqlite3')}
    file=launchdir/(label+'.plist'); file.write_bytes(plistlib.dumps(plist)); os.chmod(file,0o600)
    if label not in retained:
        subprocess.run(['launchctl','bootstrap',f'gui/{uid}',str(file)],check=True)
print('AI 서버·외부 연결·절전 방지 자동 실행 설정 완료')
print('데이터 저장: '+str(runtime/'data/preparation-images.sqlite3'))
