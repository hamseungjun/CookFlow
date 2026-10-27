import copy
import unittest
from unittest.mock import patch

import app


class RecipePhaseValidationTests(unittest.TestCase):
    def setUp(self):
        app.cached_recipe.cache_clear()
        self.body = {'dish': '두부 요리', 'ingredients': '두부', 'servings': 1}
        self.recipe = {
            'title': '두부 요리', 'servings': 1, 'waterML': 0,
            'ingredients': [{'id': 'tofu', 'name': '두부', 'amount': 150, 'unit': 'g', 'fresh': True, 'cut': '깍둑썰기'}],
            'steps': [
                {'action': 'heat', 'title': '화력 설정', 'instruction': '중불로 가열해 주세요.', 'heat': 'medium', 'seconds': 0, 'ingredientIDs': []},
                {'action': 'stir', 'title': '두부 볶기', 'instruction': '두부를 넣고 볶아 주세요.', 'heat': None, 'seconds': 60, 'ingredientIDs': ['tofu']},
                {'action': 'taste', 'title': '간 확인', 'instruction': '간을 보고 필요하면 더 끓여 주세요.', 'heat': None, 'seconds': 0, 'ingredientIDs': []},
            ], 'uncertainties': [],
        }

    def test_heat_adjustment_and_taste_do_not_require_timers(self):
        self.assertEqual(app.recipe_technique_issues(self.body, self.recipe), [])

    def test_valid_recipe_does_not_trigger_repair_generation(self):
        with patch('app.generate_recipe_openai', return_value=copy.deepcopy(self.recipe)) as generate:
            result = app.create_recipe(self.body)
        self.assertTrue(result['steps'])
        generate.assert_called_once()

    def test_actual_cooking_still_requires_time(self):
        self.recipe['steps'][1]['seconds'] = 0
        self.assertTrue(any('positive cooking timer' in s for s in app.recipe_technique_issues(self.body, self.recipe)))

    def test_actual_cooking_still_requires_heat(self):
        self.recipe['steps'][0]['heat'] = 'off'
        self.assertTrue(any('explicit heat before cooking' in s for s in app.recipe_technique_issues(self.body, self.recipe)))

    def test_explicit_preheat_still_requires_time(self):
        self.recipe['steps'][0]['instruction'] = '중불로 예열해 주세요.'
        self.assertTrue(any('preheating' in s for s in app.recipe_technique_issues(self.body, self.recipe)))

    def test_heat_action_requires_explicit_target(self):
        self.recipe['steps'][0]['heat'] = None
        self.assertTrue(any('explicit target' in s for s in app.recipe_technique_issues(self.body, self.recipe)))

    def test_unused_pantry_candidates_are_allowed(self):
        self.body['ingredients'] = '두부, 우삼겹, 숙주'
        self.assertEqual(app.recipe_technique_issues(self.body, self.recipe), [])

    def test_unavailable_ingredients_are_still_rejected(self):
        self.body['ingredients'] = '우삼겹, 숙주'
        self.assertTrue(any('unselected' in s for s in app.recipe_technique_issues(self.body, self.recipe)))

    def test_output_ingredients_must_still_be_used(self):
        self.recipe['steps'][1]['ingredientIDs'] = []
        self.assertTrue(any('no unused foods' in s for s in app.recipe_technique_issues(self.body, self.recipe)))

    def test_candidate_selection_does_not_add_unused_inventory_notes(self):
        self.body['ingredients'] = '두부, 우삼겹, 숙주'
        with patch('app.generate_recipe_openai', return_value=copy.deepcopy(self.recipe)) as generate:
            result = app.create_recipe(self.body)
        generate.assert_called_once()
        self.assertEqual([i['name'] for i in result['ingredients']], ['두부'])
        self.assertEqual(result['uncertainties'], [])
        self.assertIn('AVAILABLE PANTRY CANDIDATES', generate.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
