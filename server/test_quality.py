import array
import io
import math
import json
import os
from pathlib import Path
import random
import unittest
from unittest.mock import patch
import wave
import app
from speech_gate import speech_evidence

RATE=48000
def wav(samples, rate=RATE):
    b=io.BytesIO()
    with wave.open(b,'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(array.array('h',samples).tobytes())
    return b.getvalue()

class SpeechTests(unittest.TestCase):
    def test_silence_clatter_hum_and_stationary_noise_are_not_sent_to_asr(self):
        rng=random.Random(41)
        cases=[('silence',[0]*(RATE*3)),('clatter',[rng.randint(-13000,13000) if RATE<=i<RATE+4000 else 0 for i in range(RATE*3)]),('noise',[rng.randint(-2000,2000) for _ in range(RATE*3)]),('hum',[int(2000*math.sin(2*math.pi*120*i/RATE)) for i in range(RATE*3)])]
        for name,samples in cases:
            audio=wav(samples)
            self.assertFalse(speech_evidence(audio,'audio/wav')['accepted'],name)
            with patch('app.urllib.request.urlopen') as provider:
                self.assertEqual(app.transcribe_audio(audio,'audio/wav'),'')
                provider.assert_not_called()
    def test_clear_synthetic_korean_speech_is_accepted(self):
        audio=(Path(__file__).with_name('test_audio') / 'clear-ai-korean.wav').read_bytes()
        evidence=speech_evidence(audio,'audio/wav')
        self.assertTrue(evidence['accepted'], evidence)
    def test_malformed_and_unverified_recordings_cannot_become_commands(self):
        self.assertFalse(speech_evidence(b'not-wave','audio/wav')['accepted'])
        self.assertFalse(speech_evidence(b'compressed','audio/webm')['accepted'])
    def test_compressed_clear_speech_is_supported(self):
        audio=(Path(__file__).with_name('test_audio') / 'clear-ai-korean.m4a').read_bytes()
        self.assertTrue(speech_evidence(audio,'audio/mp4')['accepted'])
    def test_low_asr_confidence_and_foreign_hallucination_are_rejected(self):
        audio=(Path(__file__).with_name('test_audio') / 'clear-ai-korean.wav').read_bytes()
        for text,score,expected in [('넣었어요',-.05,'넣었어요'),('넣었어요',-1.0,''),('どうした。',-.05,'')]:
            with patch.dict(os.environ,{'OPENAI_API_KEY':'fixture-not-a-real-key'}), patch('app.urllib.request.urlopen') as provider:
                provider.return_value.__enter__.return_value.read.return_value=json.dumps({'text':text,'logprobs':[{'logprob':score}]}).encode()
                self.assertEqual(app.transcribe_audio(audio,'audio/wav'),expected)

class IntentTests(unittest.TestCase):
    def answers(self, probability=1, mismatch=0, control='none', control_probability=1, confidence=1):
        return {'current_action_report':{'type':'predicate','probability':probability},
                'incomplete_or_mismatched':{'type':'predicate','probability':mismatch},
                'control_request':{'type':'choice','choice':control,'confidence':confidence,'probabilities':[{'value':control,'probability':control_probability}]}}
    def decision(self, value, phase):
        answers=self.answers(probability=1 if value == 'confirm' else 0, control='skip' if value == 'skip' else 'none')
        with patch('app.decide',return_value=answers):
            return app.voice_decision({'text':'넣었어','phase':phase})['intent']
    def test_skip_never_has_permission_to_execute(self):
        for phase in ('ready','active','expired','paused'):
            self.assertEqual(self.decision('skip',phase),'keep')
    def test_confirmation_only_when_waiting_for_action(self):
        self.assertEqual(self.decision('confirm','ready'),'confirm')
        for phase in ('active','expired','paused',''):
            self.assertEqual(self.decision('confirm',phase),'keep')
    def test_full_sentence_is_classified_despite_next_step_words(self):
        with patch('app.decide',return_value=self.answers()) as provider:
            result=app.voice_decision({'text':'다음 단계 얘기가 아니라 지금 넣는 건 다 했어요','phase':'ready','required_items':['순두부']})
            self.assertEqual(result['intent'],'confirm')
            evidence=json.loads(provider.call_args.args[0])
            self.assertEqual(evidence['utterance'],'다음 단계 얘기가 아니라 지금 넣는 건 다 했어요')
            self.assertEqual(evidence['context']['required_items'],['순두부'])
            self.assertEqual([q['type'] for q in provider.call_args.args[1]],['predicate','predicate','choice'])
    def test_meaningless_stays_keep(self):
        self.assertEqual(self.decision('keep','ready'),'keep')
    def test_partial_report_cannot_confirm_even_if_report_itself_is_certain(self):
        for mismatch in (.16,.5,.99):
            self.assertEqual(app.voice_action_from_answers(self.answers(mismatch=mismatch),'ready')['intent'],'keep')
    def test_low_report_probability_keeps_state(self):
        self.assertEqual(app.voice_action_from_answers(self.answers(probability=.84),'ready')['intent'],'keep')
    def test_information_requests_do_not_confirm_a_step(self):
        for control in ('repeat','heat','remaining'):
            self.assertEqual(app.voice_action_from_answers(self.answers(control=control),'ready')['intent'],control)
    def test_refusal_or_missing_answer_keeps_state(self):
        for name in self.answers():
            answers=self.answers();answers.pop(name)
            self.assertEqual(app.voice_action_from_answers(answers,'ready')['intent'],'keep')
            answers=self.answers();answers[name]={'type':'refusal'}
            self.assertEqual(app.voice_action_from_answers(answers,'ready')['intent'],'keep')
    def test_uncertain_control_does_not_become_completion(self):
        for kwargs in ({'control':'pause','control_probability':.8},{'confidence':.4}):
            self.assertEqual(app.voice_action_from_answers(self.answers(**kwargs),'ready')['intent'],'keep')
    def test_invalid_predicate_probabilities_cannot_confirm(self):
        for value in (float('nan'),float('inf'),-1,2,None,'1',True):
            for name in ('current_action_report','incomplete_or_mismatched'):
                answers=self.answers();answers[name]['probability']=value
                self.assertEqual(app.voice_action_from_answers(answers,'ready')['intent'],'keep')
    @patch('app.generate')
    def test_noun_repair_preserves_negation_and_does_not_change_named_food(self,generate):
        generate.return_value={'corrections':[{'source':'재려','target':'재료'}, {'source':'안','target':'다'}]}
        self.assertEqual(app.repair_voice_nouns('재려 안 넣었다고',{}),'재료 안 넣었다고')
        generate.return_value={'corrections':[{'source':'재려','target':'양파'}]}
        self.assertEqual(app.repair_voice_nouns('재려 넣었다고',{}),'재려 넣었다고')
    @patch('app.generate')
    def test_normal_sentences_do_not_need_a_repair_request(self,generate):
        for text in ('재료 넣었어','양파만 넣었어','아직 안 넣었어','넣어도 돼?'):
            self.assertEqual(app.repair_voice_nouns(text,{}),text)
        generate.assert_not_called()
    def test_keep_reason_separates_uncertain_meaning_from_noncompletion(self):
        result=app.voice_action_from_answers(self.answers(probability=.02),'ready')
        self.assertEqual(result['intent'],'keep');self.assertEqual(result['reason'],'not_completion')
        result=app.voice_action_from_answers(self.answers(probability=.52),'ready')
        self.assertEqual(result['reason'],'uncertain')
    def test_request_sends_setup_goal_separate_from_full_cooking_instruction(self):
        with patch('app.decide',return_value=self.answers()) as provider:
            app.voice_decision({'text':'다 넣었어','phase':'ready','instruction':'양파를 넣고 볶아주세요.','confirmation_goal':'양파 투입 확인만 합니다.'})
            evidence=json.loads(provider.call_args.args[0])
            self.assertEqual(evidence['context']['instruction'],'양파 투입 확인만 합니다.')
            self.assertNotIn('볶아', evidence['context']['instruction'])

class RecipeTests(unittest.TestCase):
    def setUp(self): app.cached_recipe.cache_clear()
    def result(self):
        return {'servings':1,'waterML':250,'ingredients':[{'id':'tofu','name':'순두부','amount':350,'unit':'g'}, {'id':'water','name':'물','amount':250,'unit':'ml'}], 'steps':[{'title':'끓이기','instruction':'순두부를 넣고 끓여주세요.','action':'simmer','heat':'medium','seconds':180,'ingredientIDs':['tofu','water']}]}
    def body(self): return {'dish':'순두부찌개','servings':1,'ingredients':'순두부'}
    def test_normal_recipe_passes(self):
        result=self.result();body=self.body()
        self.assertEqual(app.recipe_technique_issues(body,result),[])
        self.assertEqual(app.recipe_quantity_issues(body,result),[])
    def test_forgotten_ingredient_and_heat_and_timer_are_rejected(self):
        for field,value in [('ingredientIDs',['water']),('heat',None),('seconds',0)]:
            result=self.result();result['steps'][0][field]=value
            self.assertTrue(app.recipe_technique_issues(self.body(),result),field)
    def test_unselected_seasoning_is_rejected(self):
        result=self.result();result['ingredients'].append({'id':'salt','name':'소금','amount':8,'unit':'g'})
        result['steps'][0]['ingredientIDs'].append('salt')
        self.assertTrue(app.recipe_technique_issues(self.body(),result))
    @patch('app.generate')
    def test_bad_quantity_is_repaired_once(self,generate):
        bad=self.result();bad['ingredients'][0]['amount']=700
        generate.side_effect=[bad,self.result()]
        result=app.create_recipe(self.body())
        self.assertEqual(result['ingredients'][0]['amount'],350)
        self.assertEqual(generate.call_count,2)
    @patch('app.generate')
    def test_cached_validated_result_is_reused_without_mutable_aliasing(self,generate):
        generate.return_value=self.result()
        first=app.create_recipe(self.body())
        first['ingredients'][0]['amount']=9999
        second=app.create_recipe(self.body())
        self.assertEqual(second['ingredients'][0]['amount'],350)
        self.assertEqual(generate.call_count,1)
    @patch('app.generate')
    def test_changed_preferences_do_not_reuse_old_result(self,generate):
        generate.return_value=self.result()
        app.create_recipe(self.body())
        body=self.body();body['salt']=0
        app.create_recipe(body)
        self.assertEqual(generate.call_count,2)
    @patch('app.generate')
    def test_failed_validation_is_never_cached(self,generate):
        bad=self.result();bad['ingredients'][0]['amount']=900
        generate.side_effect=[bad,bad,self.result()]
        with self.assertRaises(ValueError): app.create_recipe(self.body())
        self.assertEqual(app.create_recipe(self.body())['ingredients'][0]['amount'],350)
        self.assertEqual(generate.call_count,3)
    def test_compacted_baseline_keeps_cooking_and_quantity_constraints(self):
        baseline={'menu':'sundubu','preferences':{'servings':1},'waterML':250,'items':[{'amount':350,'ingredient':{'id':'tofu','name':'순두부','unit':'g','category':'식재료','cut':'그대로 준비'}}], 'steps':[{'title':'끓이기','instruction':'두부를 넣어주세요.','actionType':'simmer','heatTo':'medium','durationSeconds':180,'safetyNotice':'끓으면 불을 줄이세요.'}], 'kitchen':{'deviceSetting':'7단계'},'id':'irrelevant'}
        compact=app.compact_recipe_baseline(baseline)
        self.assertEqual(app.recipe_quantity_plan({'baseline_recipe':compact,'servings':2})[0]['amount'],700)
        self.assertEqual(compact['steps'][0]['safetyNotice'],'끓으면 불을 줄이세요.')
        self.assertEqual(compact['steps'][0]['heatTo'],'medium')
        baseline['id']='new-id';baseline['kitchen']={'deviceSetting':'다이얼'}
        self.assertEqual(app.compact_recipe_baseline(baseline),compact)
    def test_rules_are_loaded_from_file(self):
        self.assertEqual(app.RECIPE_RULES['version'],1)
        self.assertTrue(app.RECIPE_RULES['generation'])

if __name__=='__main__': unittest.main(verbosity=2)
