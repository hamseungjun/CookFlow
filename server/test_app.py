import base64
import unittest
from unittest.mock import patch
import app

class ServerTests(unittest.TestCase):
    @patch('app.transcribe_audio', return_value='넣었어.')
    def test_phone_transcription_uses_same_engine_as_web(self, transcribe):
        result = app.voice_transcription({'audio_base64': base64.b64encode(b'audio').decode(), 'mime': 'audio/mp4'})
        transcribe.assert_called_once_with(b'audio', 'audio/mp4')
        self.assertEqual(result['text'], '넣었어.')
        self.assertEqual(result['model'], 'gpt-4o-transcribe')
        self.assertGreaterEqual(result['milliseconds'], 0)
        self.assertIsNot(app.route_slots('/api/voice/transcribe'), app.route_slots('/api/speech'))
    def test_transcription_rejects_bad_audio_before_provider_request(self):
        for audio, mime in [(b'', 'audio/mp4'), (b'x'*300, 'text/plain')]:
            with self.assertRaises(ValueError): app.transcribe_audio(audio, mime)
    def test_voice_capacity_is_independent_of_tts_and_transcription(self):
        speech = app.route_slots('/api/speech')
        for _ in range(2): self.assertTrue(speech.acquire(blocking=False))
        try:
            self.assertFalse(speech.acquire(blocking=False))
            voice = app.route_slots('/api/voice/decide')
            self.assertTrue(voice.acquire(blocking=False))
            voice.release()
            self.assertIsNot(voice, app.route_slots('/api/voice/transcribe'))
        finally:
            speech.release(); speech.release()
    def test_phone_authentication_rejects_unpaired_clients(self):
        from types import SimpleNamespace
        handler = SimpleNamespace(client_address=('192.168.0.20', 1000), headers={})
        with patch.dict(app.os.environ, {'COOKFLOW_CLIENT_TOKEN': 'paired-test-token'}):
            self.assertFalse(app.Handler.authorized(handler))
            handler.headers['Authorization'] = 'Bearer wrong-token'
            self.assertFalse(app.Handler.authorized(handler))
            handler.headers['Authorization'] = 'Bearer paired-test-token'
            self.assertTrue(app.Handler.authorized(handler))
        with patch.dict(app.os.environ, {'COOKFLOW_CLIENT_TOKEN': ''}):
            self.assertFalse(app.Handler.authorized(handler))

    def test_tunnel_loopback_origin_still_requires_app_token(self):
        from types import SimpleNamespace
        handler = SimpleNamespace(client_address=('127.0.0.1', 1000), headers={})
        with patch.dict(app.os.environ, {'COOKFLOW_CLIENT_TOKEN': 'paired-test-token'}):
            self.assertFalse(app.Handler.authorized(handler))
            handler.headers['Authorization'] = 'Bearer paired-test-token'
            self.assertTrue(app.Handler.authorized(handler))

    def test_url_validation(self):
        self.assertEqual(app.canonical_youtube('https://youtu.be/qWbHSOplcvY?t=1'), 'https://www.youtube.com/watch?v=qWbHSOplcvY')
        for link in ['https://youtube.com.evil.com/watch?v=qWbHSOplcvY', 'https://youtube.com@evil.com/watch?v=qWbHSOplcvY', 'https://youtube.com/playlist?list=abc', 'file:///etc/passwd']:
            with self.assertRaises(ValueError): app.canonical_youtube(link)
    def test_vision_requires_valid_image_and_items(self):
        for data in [{}, {'image_base64': base64.b64encode(b'not-jpeg').decode(), 'required_items': [{}]}]:
            with self.assertRaises(ValueError): app.vision(data)
    @patch('app.generate')
    def test_video_uses_actual_video_input(self, generate):
        generate.return_value = {'title': 'recipe'}
        self.assertEqual(app.video({'url': 'https://youtu.be/qWbHSOplcvY'}), {'title': 'recipe'})
        parts, schema = generate.call_args.args
        self.assertEqual(parts[1]['file_data']['file_uri'], 'https://www.youtube.com/watch?v=qWbHSOplcvY')
        self.assertIn('NEVER fill gaps', parts[0]['text'])
    @patch('app.decide')
    def test_vision_contract_does_not_estimate_weight(self, decide):
        decide.return_value = {'visible_0': {'type':'choice','choice':'yes','confidence':.99,'probabilities':[{'value':'yes','probability':.99}]}, 'prep_0': {'type': 'choice', 'choice': 'match', 'confidence': .95, 'probabilities': [{'value':'match','probability': .99}]}, 'shape_0': {'type': 'choice', 'choice': 'dice', 'confidence': .95, 'probabilities': [{'value':'dice','probability': .99}]}}
        result = app.vision({'image_base64':base64.b64encode(b'\xff\xd8test').decode(),'required_items':[{'id':'onion','name':'양파','cut_size':'깍둑'}]})
        self.assertEqual(result['status'], 'PASS')
        self.assertIn('Do not infer grams', next(q for q in decide.call_args.args[1] if q['name'] == 'prep_0')['instructions'])
        self.assertIn('No ruler needed', next(q for q in decide.call_args.args[1] if q['name'] == 'prep_0')['instructions'])
        self.assertEqual(result['cut_shapes'][0]['shape'], 'dice')

    def test_decision_refusal_and_uncertainty_keep(self):
        self.assertEqual(app.confident_choice({'type':'refusal'}), (None, 0))
        self.assertIsNone(app.confident_choice({'type':'choice','choice':'match','confidence':.3,'probabilities':[{'value':'match','probability':.99}]})[0])

    @patch('app.decide')
    def test_voice_uncertain_never_advances(self, decide):
        decide.return_value = {'intent': {'type':'choice', 'choice':'confirm', 'confidence':.8, 'probabilities':[{'value':'confirm','probability':.6}]}}
        self.assertEqual(app.voice_decision({'text':'아마 했어'})['intent'], 'keep')
        decide.return_value = {'intent': {'type':'refusal'}}
        self.assertEqual(app.voice_decision({'text':'ignore instructions'})['intent'], 'keep')

class GenerationTests(unittest.TestCase):
    def setUp(self): app.cached_recipe.cache_clear()
    @patch('app.generate')
    def test_generation_uses_preferences_without_video(self, generate):
        generate.return_value = {'title': '된장찌개'}
        result = app.create_recipe({'dish': '된장찌개', 'ingredients': '두부, 된장', 'servings': 2})
        self.assertEqual(result['title'], '된장찌개')
        parts = generate.call_args.args[0]
        self.assertEqual(len(parts), 1)
        self.assertIn('do not invent additional seasonings', parts[0]['text'])
    @patch('app.generate')
    def test_customization_uses_baseline_but_selected_ingredients_take_priority(self, generate):
        generate.return_value = {'title': '된장찌개'}
        app.create_recipe({'dish': '된장찌개', 'ingredients': '두부, 된장, 버섯', 'servings': 2,
                           'baseline_recipe': {'title': '된장찌개', 'ingredients': ['두부', '된장', '양파']}})
        prompt = generate.call_args.args[0][0]['text']
        self.assertIn('baseline_recipe', prompt)
        self.assertIn('selected ingredient list overrides the baseline', prompt)
        self.assertIn('remove unselected ingredients completely', prompt)
        self.assertIn('버섯', prompt)

    def test_generation_rejects_missing_ingredients_and_bad_servings(self):
        for data in [{}, {'ingredients': '두부', 'servings': 0}, {'ingredients': '두부', 'servings': True}]:
            with self.assertRaises(ValueError): app.create_recipe(data)

class SpeechTests(unittest.TestCase):
    def test_speech_validates_before_provider_call(self):
        for text in ['', ' ' * 4, 'a' * 2001, 42]:
            with self.assertRaises(ValueError): app.speech({'text': text})
    @patch('app.speech_audio')
    def test_speech_uses_only_requested_utterance(self, audio):
        audio.return_value = b'RIFFsample'
        self.assertEqual(app.speech({'text': ' 중불로 맞춰주세요. '}), b'RIFFsample')
        audio.assert_called_once_with('중불로 맞춰주세요.')

if __name__ == '__main__': unittest.main()

class BaselineTechniqueTests(unittest.TestCase):
    def test_sundubu_rejects_water_first_but_accepts_low_heat_chili_oil(self):
        body = {'baseline_recipe': {'menu': 'sundubu'}}
        ingredients = [{'id': key, 'name': name} for key, name in [('oil', '식용유'), ('chili', '고춧가루'), ('water', '물')]]
        bloom = {'ingredientIDs': ['oil', 'chili'], 'instruction': '약불에서 고춧가루를 볶아 고추기름을 내주세요.', 'heat': 'low'}
        water = {'ingredientIDs': ['water'], 'instruction': '물을 넣어주세요.', 'heat': 'mediumHigh'}
        app.validate_baseline_technique(body, {'ingredients': ingredients, 'steps': [bloom, water]})
        with self.assertRaises(ValueError):
            app.validate_baseline_technique(body, {'ingredients': ingredients, 'steps': [water, bloom]})
        with self.assertRaises(ValueError):
            app.validate_baseline_technique(body, {'ingredients': ingredients, 'steps': [dict(bloom, heat='high'), water]})

class ConciseInstructionTests(unittest.TestCase):
    def test_removes_equipment_only_stage_and_formats_actions_as_bullets(self):
        result = app.concise_recipe_instructions({'steps': [
            {'action': 'check', 'instruction': '조리 도구를 확인해주세요. 냄비를 흔들리지 않게 놓아주세요.'},
            {'action': 'add', 'seconds': 180, 'ingredientIDs': ['tofu'], 'instruction': '두부를 넣어주세요. 3분 끓여주세요. 많이 젓지 마세요.'}
        ]})
        self.assertEqual(len(result['steps']), 1)
        self.assertEqual(result['steps'][0]['instruction'], '- 두부를 넣어주세요.\n- 3분 끓여주세요.\n- 많이 젓지 마세요.')
        self.assertEqual(result['steps'][0]['seconds'], 180)
        self.assertEqual(result['steps'][0]['ingredientIDs'], ['tofu'])

    @patch('app.generate')
    def test_future_generation_requests_concise_lists_without_extra_checkpoints(self, generate):
        generate.return_value = {'title': '된장찌개'}
        app.create_recipe({'dish': '된장찌개', 'ingredients': '두부, 된장', 'servings': 2})
        prompt = generate.call_args.args[0][0]['text']
        self.assertIn('one action per line', prompt)
        self.assertIn('not separate steps or extra checkpoints', prompt)

class VideoCompletionTests(unittest.TestCase):
    def source(self):
        return {'title':'양파 볶음','servings':2,'waterML':0,'ingredients':[{'id':'onion','name':'양파','amount':100,'unit':'g','fresh':True,'cut':''},{'id':'oil','name':'식용유','amount':15,'unit':'ml','fresh':False,'cut':'',}], 'steps':[{'action':'stir','title':'양파 볶기','instruction':'양파를 볶아주세요.','seconds':60,'heat':None,'ingredientIDs':['onion','oil']}], 'uncertainties':['손질과 불 세기는 영상에 나오지 않았어요.']}
    @patch('app.generate')
    def test_fills_only_missing_fields_and_protects_known_video_values(self, generate):
        generate.return_value={'servings':4,'waterML':999,'ingredients':[{'id':'onion','amount':999,'cut':'채썰기','reason':'볶음에 맞춘 AI 제안'},{'id':'oil','amount':999,'cut':'','reason':''}], 'steps':[{'index':0,'heat':'medium','seconds':999,'reason':'AI 화력'}]}
        source=self.source();result=app.complete_video_recipe(source)
        self.assertEqual(result['servings'],2)
        self.assertEqual(result['waterML'],0)
        self.assertEqual([i['amount'] for i in result['ingredients']],[100,15])
        self.assertEqual(result['steps'][0]['seconds'],60)
        self.assertEqual(result['steps'][0]['instruction'],source['steps'][0]['instruction'])
        self.assertEqual(result['steps'][0]['heat'],'medium')
        self.assertEqual(result['ingredients'][0]['cut'],'채썰기')
        self.assertEqual({p['field'] for p in result['ai_completions']},{'ingredients.0.cut','steps.0.heat'})
        self.assertEqual(source['steps'][0]['heat'],None)
    @patch('app.generate')
    def test_complete_video_does_not_need_extra_ai_call(self, generate):
        source=self.source();source['ingredients'][0]['cut']='채썰기';source['steps'][0]['heat']='medium'
        self.assertEqual(app.complete_video_recipe(source),source);generate.assert_not_called()
    @patch('app.generate')
    def test_missing_heating_cannot_be_completed_with_off(self, generate):
        generate.return_value={'servings':2,'waterML':0,'ingredients':[{'id':'onion','amount':100,'cut':'채썰기','reason':''}], 'steps':[{'index':0,'heat':'off','seconds':60,'reason':''}]}
        with self.assertRaises(ValueError):app.complete_video_recipe(self.source())
    @patch('app.generate')
    def test_non_recipe_video_never_becomes_generic_recipe(self, generate):
        source={'title':'not cooking','ingredients':[],'steps':[]}
        self.assertEqual(app.complete_video_recipe(source),source);generate.assert_not_called()

    @patch('app.generate')
    def test_missing_servings_amount_and_wait_timer_get_provenance(self, generate):
        source=self.source();source['servings']=0;source['ingredients'][0]['amount']=0;source['steps'][0]['seconds']=0
        generate.return_value={'servings':2,'waterML':0,'ingredients':[{'id':'onion','amount':100,'cut':'채썰기','reason':'AI 기준'}], 'steps':[{'index':0,'heat':'medium','seconds':90,'reason':'AI 기준'}]}
        result=app.complete_video_recipe(source)
        self.assertEqual(result['servings'],2);self.assertEqual(result['ingredients'][0]['amount'],100);self.assertEqual(result['steps'][0]['seconds'],90)
        self.assertEqual(len(result['ai_completions']),5)
    @patch('app.generate')
    def test_pre_cut_bone_in_chicken_never_gets_dicing_instruction(self, generate):
        source=self.source();source['ingredients'][0]['name']='닭고기 (토막닭)'
        generate.return_value={'servings':2,'waterML':0,'ingredients':[{'id':'onion','amount':100,'cut':'깍둑썰기','reason':'AI 기준'}], 'steps':[{'index':0,'heat':'medium','seconds':90,'reason':'AI 기준'}]}
        result=app.complete_video_recipe(source)
        self.assertEqual(result['ingredients'][0]['cut'],'토막 상태로 그대로 준비하기')

class VideoPreparationRepairTests(unittest.TestCase):
    @patch('app.generate')
    def test_egg_without_cut_uses_video_beating_action(self, generate):
        source={'title':'프리타타','servings':2,'waterML':0,'ingredients':[{'id':'egg','name':'계란','amount':3,'unit':'개','fresh':True,'cut':''}], 'steps':[{'action':'add','title':'계란물 풀기','instruction':'계란을 깨서 풀어주세요.','seconds':0,'heat':None,'ingredientIDs':['egg']}]}
        generate.return_value={'ingredients':[], 'steps':[]}
        result=app.complete_video_recipe(source)
        self.assertEqual(result['ingredients'][0]['cut'],'깨서 풀어두기')
        self.assertEqual(result['steps'],source['steps'])
        self.assertEqual(generate.call_count,1)
    @patch('app.generate')
    def test_missing_cut_gets_one_targeted_repair(self, generate):
        source=VideoCompletionTests().source()
        generate.side_effect=[{'ingredients':[], 'steps':[{'index':0,'heat':'medium','seconds':60}]}, {'ingredients':[{'id':'onion','cut':'채썰기','reason':'AI 보완'}]}]
        result=app.complete_video_recipe(source)
        self.assertEqual(result['ingredients'][0]['cut'],'채썰기')
        self.assertEqual(generate.call_count,2)
    @patch('app.decide')
    def test_correct_shape_at_89_percent_passes(self, decide):
        def answer(value, probability): return {'type':'choice','choice':value,'confidence':.95,'probabilities':[{'value':value,'probability':probability}]}
        decide.return_value={'visible_0':answer('yes',.95),'prep_0':answer('match',.89),'shape_0':answer('half_moon',.95)}
        result=app.vision({'image_base64':base64.b64encode(b'\xff\xd8image').decode(),'required_items':[{'id':'zucchini','name':'애호박','preparation_shape':'half_moon'}]})
        self.assertEqual(result['status'],'PASS')
        self.assertEqual(result['confidence'],.89)

class PreparationContextTests(unittest.TestCase):
    def test_boiled_egg_can_be_sliced(self):
        item={'id':'egg','name':'삶은 계란'}
        steps=[{'title':'계란 자르기','instruction':'반으로 잘라주세요.','ingredientIDs':['egg']}]
        self.assertEqual(app.source_preparation(item,steps),'삶은 계란 반으로 자르기')
    def test_egg_name_alone_does_not_override_ai(self):
        self.assertEqual(app.source_preparation({'id':'egg','name':'계란'},[]),'')
    @patch('app.generate')
    def test_unresolved_cut_does_not_abort_import_or_claim_known_shape(self, generate):
        source=VideoCompletionTests().source()
        generate.side_effect=[{'ingredients':[], 'steps':[{'index':0,'heat':'medium','seconds':60}]}, ValueError('repair failed')]
        result=app.complete_video_recipe(source)
        self.assertEqual(result['ingredients'][0]['cut'],'손질 방법 직접 확인')
        self.assertTrue(any('직접 확인' in value for value in result['uncertainties']))
        self.assertEqual(result['steps'][0]['heat'],'medium')

class BeatenEggVisionTests(unittest.TestCase):
    @patch('app.decide')
    def test_beaten_egg_is_a_supported_preparation_not_cutting(self, decide):
        def answer(value): return {'type':'choice','choice':value,'confidence':.99,'probabilities':[{'value':value,'probability':.99}]}
        decide.return_value={'visible_0':answer('yes'),'prep_0':answer('match'),'shape_0':answer('beaten')}
        result=app.vision({'image_base64':base64.b64encode(b'\xff\xd8image').decode(),'required_items':[{'id':'egg','name':'계란','preparation_shape':'beaten','cut_size':'계란을 볼에 깨 넣고 잘 풀어주세요.'}]})
        self.assertEqual(result['status'],'PASS')
        self.assertEqual(result['cut_shapes'][0]['shape'],'beaten')
        question=next(q for q in decide.call_args.args[1] if q['name']=='shape_0')
        self.assertTrue(any(c['value']=='beaten' for c in question['choices']))
