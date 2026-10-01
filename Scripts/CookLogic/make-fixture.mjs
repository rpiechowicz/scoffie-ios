// Odświeża `kotlet.json` ze scenariusza wzorcowego w repo backendu.
// Uruchomienie (z katalogu scoffie-ios, backend obok):
//   node Scripts/CookLogic/make-fixture.mjs [../scoffie-backend]
//
// Scenariusz w backendzie wskazuje składniki NAZWĄ (id różnią się między
// bazami); tu dostają stałe id 0000…0001–0012 w kolejności przepisu,
// a składniki przepisu — działy i miarę kuchenną przypraw jak ze szczegółu.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const backend = process.argv[2] ?? '../scoffie-backend';
const file = JSON.parse(readFileSync(join(backend, 'prisma/catalog/cook-scenarios-pl-v1.json'), 'utf8'));
const scenario = file.scenarios.find((s) => s.recipeId === '70d8db3e-e896-460e-ba96-d53d02c1357f');

// Przepis wzorcowy (§10.1 workstreamu): nazwa, ilość, jednostka, dział.
const ingredients = [
  ['filet z kurczaka', 320, 'g', 'Mięso'],
  ['masło', 30, 'g', 'Nabiał i jajko'],
  ['koperek', 10, 'g', 'Warzywa'],
  ['jajko', 1, 'szt', 'Nabiał i jajko'],
  ['mąka pszenna', 20, 'g', 'Zboża i makarony'],
  ['bułka tarta', 50, 'g', 'Piekarnia'],
  ['olej rzepakowy', 30, 'ml', 'Olej i tłuszcz'],
  ['ziemniak', 500, 'g', 'Warzywa'],
  ['ogórek', 250, 'g', 'Warzywa'],
  ['śmietana 12', 60, 'g', 'Nabiał i jajko'],
  ['sól', 3, 'g', 'Przyprawy i sosy'],
  ['pieprz czarny', 1, 'g', 'Przyprawy i sosy'],
];
// Gramy na łyżeczkę — `src/recipes/ingredient-amount.util.ts` w backendzie.
const measure = { 'sól': { kind: 'spoon', per: 6 }, 'pieprz czarny': { kind: 'spoon', per: 2.3 } };

const id = (i) => `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`;
const byName = Object.fromEntries(ingredients.map(([name], i) => [name, id(i)]));
const content = structuredClone(scenario.content);
for (const step of content.steps) {
  step.ingredients = step.ingredients.map(({ ingredient, ...rest }) => ({ ingredientId: byName[ingredient], ...rest }));
  step.mentions = step.mentions.map((name) => byName[name]);
}

const out = {
  response: { recipeId: scenario.recipeId, scenario: { version: 1, rulesVersion: file.rulesVersion, content } },
  recipeIngredients: ingredients.map(([name, amount, unit, department], i) => ({
    ingredientId: id(i),
    name: name[0].toUpperCase() + name.slice(1),
    amount,
    unit,
    department,
    kitchenMeasure: measure[name] ?? null,
  })),
};
writeFileSync(new URL('./kotlet.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(`kotlet.json: ${content.steps.length} kroków, zasady ${file.rulesVersion}`);
