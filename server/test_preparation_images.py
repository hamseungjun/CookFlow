import tempfile
import threading
import time
import unittest
from pathlib import Path
from preparation_images import PreparationImages
PNG = b'\x89PNG\r\n\x1a\nfixture'

class PreparationImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'images.sqlite3'
        self.calls = 0
        def generate(spec):
            self.calls += 1
            time.sleep(0.04)
            return PNG
        self.store = PreparationImages(self.path, generate)
    def tearDown(self):
        self.store.pool.shutdown(wait=True)
        self.temp.cleanup()
    def ready(self, store, key):
        for _ in range(100):
            result = store.result(key)
            if result['status'] in ('ready', 'failed'): return result
            time.sleep(.01)
        self.fail('job did not finish')
    def test_recipe_independent_reuse_and_restart(self):
        first = self.store.request({'ingredient':'양파','shape':'dice','method':'양파를 깍둑 썰어주세요'})
        self.assertEqual(self.ready(self.store, first['id'])['status'], 'ready')
        second = self.store.request({'ingredient':' 양파 ','shape':'dice','method':'다른 레시피: 큼직한 양파 조각'})
        self.assertEqual(first['id'], second['id'])
        self.assertEqual(self.calls, 1)
        reopened = PreparationImages(self.path, lambda _: self.fail('cache must persist'))
        try: self.assertEqual(reopened.result(first['id'])['status'], 'ready')
        finally: reopened.pool.shutdown(wait=True)
    def test_concurrent_requests_generate_once(self):
        keys=[]
        workers=[threading.Thread(target=lambda: keys.append(self.store.request({'ingredient':'마늘','shape':'chopped'})['id'])) for _ in range(8)]
        for w in workers: w.start()
        for w in workers: w.join()
        self.assertEqual(len(set(keys)),1)
        self.assertEqual(self.ready(self.store, keys[0])['status'],'ready')
        self.assertEqual(self.calls,1)
    def test_different_shapes_and_slice_details_do_not_mix(self):
        def key(shape, method=''):
            return self.store.request({'ingredient':'양파','shape':shape,'method':method})['id']
        self.assertNotEqual(key('dice'), key('julienne'))
        self.assertNotEqual(key('slice','어슷 썰기'),key('slice','송송 썰기'))
    def test_failure_only_retries_explicitly(self):
        self.store.generate=lambda _: (_ for _ in ()).throw(ValueError('private provider error'))
        spec={'ingredient':'두부','shape':'dice'}
        result=self.store.request(spec)
        failed=self.ready(self.store,result['id'])
        self.assertEqual(failed['status'],'failed')
        self.assertNotIn('private',failed['error'])
        self.assertEqual(self.store.request(spec)['status'],'failed')
        self.store.generate=lambda _: PNG
        self.store.request(dict(spec,retry=True))
        self.assertEqual(self.ready(self.store,result['id'])['status'],'ready')
    def test_freeform_preparation_generates_and_keeps_method_in_cache_key(self):
        first = self.store.request({'ingredient': '숙주', 'shape': 'reference', 'method': '헹궈 물기 빼기'})
        self.assertEqual(self.ready(self.store, first['id'])['status'], 'ready')
        changed = self.store.request({'ingredient': '숙주', 'shape': 'reference', 'method': '데친 후 물기 빼기'})
        self.assertNotEqual(first['id'], changed['id'])
    def test_invalid_inputs_and_keys(self):
        for spec in ({'ingredient':'양파','shape':'nonsense'},{'ingredient':'','shape':'dice'}):
            with self.assertRaises(ValueError): self.store.request(spec)
        with self.assertRaises(ValueError): self.store.result('../secret')

if __name__=='__main__': unittest.main()
