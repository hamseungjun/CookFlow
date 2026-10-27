from pathlib import Path
import subprocess,sys,urllib.request
root=Path(__file__).resolve().parents[1]
try:
 with urllib.request.urlopen('http://localhost:8787/health',timeout=2) as r:
  if r.status==200:print('음성 테스트 실행 중: http://localhost:8787');raise SystemExit()
except OSError:pass
with (root/'.build/voice-lab.log').open('ab') as log:
 p=subprocess.Popen([sys.executable,str(root/'server/voice_lab_server.py')],cwd=root,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
(root/'.build/voice-lab.pid').write_text(str(p.pid))
print('맥 음성 테스트: http://localhost:8787')
