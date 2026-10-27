"""Persistent, deduplicated preparation illustrations. No camera assessment required."""
import base64
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager

VERSION = 'prep-photo-v1'
SHAPES = {'dice', 'chopped', 'julienne', 'half_moon', 'slice', 'whole', 'beaten', 'reference'}
METHODS = {'dice': 'rough bite-sized pieces (natural curved onion layers are fine, not perfect solid cubes)', 'chopped': 'finely minced pieces, not paste', 'julienne': 'thin elongated strips', 'half_moon': 'half-circle slices', 'slice': 'slices matching the requested preparation', 'whole': 'washed ready-to-cook whole ingredient', 'beaten': 'raw eggs thoroughly beaten in a small bowl'}

class PreparationImages:
    def __init__(self, db_path=None, generator=None):
        self.path = Path(db_path or os.environ.get('COOKFLOW_IMAGE_DB', Path(__file__).parent / 'data' / 'preparation-images.sqlite3'))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.generate = generator or generate_image
        self.lock = threading.Lock()
        self.pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix='prep-image')
        self.pending = set()
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS images (id TEXT PRIMARY KEY, spec TEXT NOT NULL, status TEXT NOT NULL, image BLOB, error TEXT, updated REAL NOT NULL)')
            db.execute("UPDATE images SET status='queued' WHERE status='generating'")
        os.chmod(self.path, 0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            db.execute('PRAGMA journal_mode=WAL')
            with db:
                yield db
        finally:
            db.close()

    def request(self, body):
        name = body.get('ingredient', '')
        shape = body.get('shape', '')
        method = body.get('method', '')
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80 or shape not in SHAPES or not isinstance(method, str) or len(method) > 250:
            raise ValueError('재료와 손질 방법을 확인해주세요.')
        # Known shapes share assets across recipe quantities and wording variants.
        spec = {'ingredient': ''.join(name.split()), 'shape': shape, 'method': ' '.join(method.split()) if shape in ('slice', 'reference') else '', 'version': VERSION}
        key = hashlib.sha256(json.dumps(spec, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
        with self.connect() as db:
            db.execute('INSERT OR IGNORE INTO images VALUES (?,?,?,NULL,NULL,?)', (key, json.dumps(spec, ensure_ascii=False), 'queued', time.time()))
            if body.get('retry') is True:
                db.execute("UPDATE images SET status='queued',error=NULL,updated=? WHERE id=? AND status='failed'", (time.time(), key))
        return self.result(key)

    def result(self, key):
        if len(key) != 64 or any(c not in '0123456789abcdef' for c in key):
            raise ValueError('이미지 주소를 확인해주세요.')
        with self.connect() as db:
            row = db.execute('SELECT spec,status,image,error FROM images WHERE id=?', (key,)).fetchone()
        if row is None:
            raise ValueError('손질 예시를 찾지 못했어요.')
        spec, status, image, error = row
        if status == 'queued':
            with self.lock:
                if key not in self.pending:
                    self.pending.add(key)
                    self.pool.submit(self.work, key, json.loads(spec))
        response = {'id': key, 'status': status, 'generated': True}
        if status == 'ready':
            response.update(image_base64=base64.b64encode(image).decode(), mime='image/png')
        elif status == 'failed':
            response['error'] = error or '예시 사진을 만들지 못했어요. 글 안내로 준비할 수 있어요.'
        return response

    def work(self, key, spec):
        try:
            with self.connect() as db:
                db.execute("UPDATE images SET status='generating',updated=? WHERE id=?", (time.time(), key))
            image = self.generate(spec)
            if not isinstance(image, bytes) or not image.startswith(b'\x89PNG\r\n\x1a\n') or len(image) > 12 * 1024 * 1024:
                raise ValueError('Invalid image')
            with self.connect() as db:
                db.execute("UPDATE images SET status='ready',image=?,error=NULL,updated=? WHERE id=?", (image, time.time(), key))
        except Exception:
            with self.connect() as db:
                db.execute("UPDATE images SET status='failed',error=?,updated=? WHERE id=?", ('예시 사진을 만들지 못했어요. 글 안내로 준비하거나 다시 요청해주세요.', time.time(), key))
        finally:
            with self.lock:
                self.pending.discard(key)


def generate_image(spec):
    key = os.environ.get('OPENAI_API_KEY')
    if not key:
        raise ValueError('Image API key missing')
    prompt = (
        'Photorealistic natural cooking-app preparation reference photo. Landscape 3:2, directly overhead, soft daylight, clean light wooden board. '
        f"Show ONLY the ingredient {spec['ingredient']} prepared as {METHODS.get(spec['shape'], 'ready to cook according to the preparation detail; preserve its natural form unless cutting is explicitly requested')}. "
        f"Preparation detail: {spec['method']}. "
        'Everyday home cooking, visibly realistic imperfect pieces. Centered with modest space around food. '
        'For onion preserve natural curved separate layers. For tofu or meat preserve its actual food texture. '
        'For beaten eggs use a plain small bowl. No hands, knives, text, rulers, dimensions, labels, collage, or watermark. '
        'This image illustrates the requested preparation rather than an exact size requirement.'
    )
    body = {'model': os.environ.get('COOKFLOW_IMAGE_MODEL', 'gpt-image-2.5-flare'), 'prompt': prompt, 'n': 1, 'size': '1536x1024', 'quality': 'low', 'output_format': 'png'}
    req = urllib.request.Request('https://api.openai.com/v1/images/generations', data=json.dumps(body).encode(), headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=150) as response:
        result = json.loads(response.read(20 * 1024 * 1024))
    return base64.b64decode(result['data'][0]['b64_json'], validate=True)
