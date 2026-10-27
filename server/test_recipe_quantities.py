import unittest
from unittest.mock import patch
import app

class QuantityTests(unittest.TestCase):
    def setUp(self): app.cached_recipe.cache_clear()
    def body(self):
        return {'dish':'순두부찌개','ingredients':'순두부','servings':1,'baseline_recipe':{'preferences':{'servings':2},'items':[{'ingredient':{'name':'순두부','unit':'g','category':'식재료'},'amount':700}], 'waterML':500}}
    def result(self, amount=350, servings=1):
        return {'servings':servings,'waterML':250,'ingredients':[{'id':'tofu','name':'순두부','unit':'g','amount':amount}], 'steps':[{'title':'끓이기','action':'simmer','instruction':'순두부를 넣고 끓여주세요.','ingredientIDs':['tofu'],'heat':'medium','seconds':180}]}
    def test_baseline_scaled_once_and_fresh_amount_locked(self):
        body=self.body();plan=app.recipe_quantity_plan(body)
        self.assertEqual(plan[0]['amount'],350)
        self.assertEqual(app.recipe_quantity_issues(body,self.result()),[])
        self.assertTrue(app.recipe_quantity_issues(body,self.result(700)))
        body['baseline_recipe']['preferences']['servings']=1
        body['baseline_recipe']['items'][0]['amount']=350
        body['baseline_recipe']['waterML']=250
        self.assertEqual(app.recipe_quantity_issues(body,self.result()),[])
    def test_one_serving_two_pouches_rejected_even_without_baseline(self):
        result=self.result(2);result['ingredients'][0]['unit']='봉'
        self.assertTrue(app.recipe_quantity_issues({'servings':1},result))
    @patch('app.generate')
    def test_bad_batch_is_repaired_once_before_return(self, generate):
        generate.side_effect=[self.result(700),self.result(350)]
        self.assertEqual(app.create_recipe(self.body())['ingredients'][0]['amount'],350)
        self.assertEqual(generate.call_count,2)
    @patch('app.generate')
    def test_repeated_bad_recipe_never_reaches_app(self, generate):
        generate.return_value=self.result(700)
        with self.assertRaises(ValueError):app.create_recipe(self.body())
        self.assertEqual(generate.call_count,2)
    def test_wrong_servings_rejected(self):
        self.assertTrue(app.recipe_quantity_issues(self.body(),self.result(servings=2)))
