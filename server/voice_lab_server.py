"""Loopback-only voice diagnostic UI. Provider keys stay in the server."""
import base64,json,secrets,threading,time,urllib.request,urllib.error
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import app
ROOT=Path(__file__).parent/'voice_lab'
TOKEN=secrets.token_urlsafe(32)
SLOTS=threading.BoundedSemaphore(2)

def transcribe(audio,mime):
    return app.transcribe_audio(audio,mime)

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def valid_host(self): return self.headers.get('Host') in ('localhost:8787','127.0.0.1:8787')
    def send(self,status,data,kind='application/json; charset=utf-8'):
        if not isinstance(data,bytes): data=json.dumps(data,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Content-Length',str(len(data)));self.end_headers()
        try:self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError):pass
    def do_GET(self):
        if not self.valid_host():return self.send(403,{'error':'localhost에서 열어주세요.'})
        if self.path in ('/','/index.html'):
            page=(ROOT/'index.html').read_text().replace('__TEST_TOKEN__',TOKEN)
            return self.send(200,page.encode(),'text/html; charset=utf-8')
        if self.path=='/recipe.json':return self.send(200,(ROOT/'recipe.json').read_bytes())
        if self.path=='/health':return self.send(200,{'status':'ready','transcription':bool(app.os.environ.get('OPENAI_API_KEY')),'decision':bool(app.os.environ.get('OPENAI_API_KEY'))})
        return self.send(404,{'error':'Not found'})
    def do_POST(self):
        if not self.valid_host() or self.headers.get('Origin') not in (None,'http://localhost:8787','http://127.0.0.1:8787') or not secrets.compare_digest(self.headers.get('X-Test-Token',''),TOKEN):return self.send(403,{'error':'테스트 페이지를 새로 열어주세요.'})
        if not SLOTS.acquire(blocking=False):return self.send(429,{'error':'현재 음성을 처리 중입니다.'})
        try:
            n=int(self.headers.get('Content-Length','0'))
            if not 0<n<=12*1024*1024:raise ValueError('요청 크기가 올바르지 않습니다.')
            self.connection.settimeout(15);body=json.loads(self.rfile.read(n));start=time.monotonic()
            if self.path=='/api/transcribe':
                text=transcribe(base64.b64decode(body['audio'],validate=True),body['mime'])
                return self.send(200,{'text':text,'ms':round((time.monotonic()-start)*1000),'model':'gpt-4o-transcribe'})
            if self.path=='/api/decide':
                result=app.voice_decision(body);result['ms']=round((time.monotonic()-start)*1000);return self.send(200,result)
            if self.path=='/api/speech':return self.send(200,app.speech(body),'audio/wav')
            return self.send(404,{'error':'Not found'})
        except urllib.error.HTTPError as e:self.send(502,{'error':f'AI 요청 실패 ({e.code}). 인증·사용량 또는 일시적 장애를 확인해주세요.'})
        except ValueError as e:self.send(400,{'error':str(e)})
        except Exception as e:self.send(502,{'error':'서버 연결 실패: '+type(e).__name__})
        finally:SLOTS.release()
if __name__=='__main__':
    print('CookFlow voice test: http://localhost:8787',flush=True)
    ThreadingHTTPServer(('127.0.0.1',8787),Handler).serve_forever()
