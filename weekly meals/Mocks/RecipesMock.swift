import Foundation

enum RecipesMock {
    static let omelette = Recipe(
        name: "Omlet z warzywami",
        description: "Puszysty omlet z papryką, szpinakiem i serem feta.",
        favourite: true,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 15,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1510693206972-df098062cb71?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Jajka", amount: 3, unit: .piece),
            Ingredient(name: "Papryka", amount: 80, unit: .gram),
            Ingredient(name: "Szpinak", amount: 50, unit: .gram),
            Ingredient(name: "Ser feta", amount: 30, unit: .gram),
            Ingredient(name: "Sól", amount: 1, unit: .pinch, department: "Przyprawy i sosy"),
            Ingredient(name: "Masło", amount: 10, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Pokrój papryką w drobną kostkę, a szpinak posiekaj."),
            PreparationStep(stepNumber: 2, instruction: "Rozbij jajka do miski i ubij je widelcem na gładką masę."),
            PreparationStep(stepNumber: 3, instruction: "Rozgrzej patelnię z masłem na średnim ogniu."),
            PreparationStep(stepNumber: 4, instruction: "Podsmaż papryką przez 2-3 minuty, następnie dodaj szpinak."),
            PreparationStep(stepNumber: 5, instruction: "Wlej jajka na patelnię i smaż przez około 3 minuty, aż zaczną się ściskać."),
            PreparationStep(stepNumber: 6, instruction: "Posyp pokruszonym serem feta i złóż omlet na pół. Smaż jeszcze minutę.")
        ],
        nutrition: Nutrition(kcal: 520, protein: 32, fat: 38, carbs: 8, fiber: 2, salt: 2)
    )

    static let tomatoSoup = Recipe(
        name: "Zupa pomidorowa",
        description: "Klasyczna pomidorowa z makaronem.",
        favourite: false,
        category: .lunch,
        servings: 4,
        prepTimeMinutes: 30,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Pomidory", amount: 800, unit: .gram),
            Ingredient(name: "Bulion warzywny", amount: 1, unit: .liter),
            Ingredient(name: "Makaron", amount: 200, unit: .gram),
            Ingredient(name: "Śmietanka", amount: 50, unit: .milliliter)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Obierz pomidory ze skórki, sparzone wcześniej we wrzątku."),
            PreparationStep(stepNumber: 2, instruction: "Pokrój pomidory i zblenduj na gładką masę."),
            PreparationStep(stepNumber: 3, instruction: "W garnku zagotuj bulion warzywny."),
            PreparationStep(stepNumber: 4, instruction: "Dodaj zblendowane pomidory do bulionu i gotuj 15 minut."),
            PreparationStep(stepNumber: 5, instruction: "Oddzielnie ugotuj makaron zgodnie z instrukcją na opakowaniu."),
            PreparationStep(stepNumber: 6, instruction: "Dodaj śmietankę do zupy, wymieszaj i dopraw solą i pieprzem."),
            PreparationStep(stepNumber: 7, instruction: "Podawaj zupę z ugotowanym makaronem.")
        ],
        nutrition: Nutrition(kcal: 1200, protein: 40, fat: 20, carbs: 200, fiber: 12, salt: 5),
        // Mock „thermomixowy" — zasila podglądy badge'a, filtra i przycisku
        // „Gotuj w Thermomixie" (id z prawdziwego Leczo na cookidoo.pl).
        sourceProvider: "cookidoo",
        sourceRecipeId: "r56899"
    )

    static let chickenBowl = Recipe(
        name: "Miska z kurczakiem i ryżem",
        description: "Wysokobiałkowy posiłek z warzywami.",
        favourite: true,
        category: .dinner,
        servings: 2,
        prepTimeMinutes: 25,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Pierś z kurczaka", amount: 300, unit: .gram),
            Ingredient(name: "Ryż basmati (suchy)", amount: 150, unit: .gram),
            Ingredient(name: "Brokuł", amount: 200, unit: .gram),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Przyprawy", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj ryż basmati zgodnie z instrukcją na opakowaniu."),
            PreparationStep(stepNumber: 2, instruction: "Pokrój pierś z kurczaka na mniejsze kawałki i przypraw solą, pieprzem oraz ulubionymi przyprawami."),
            PreparationStep(stepNumber: 3, instruction: "Rozgrzej patelnię z oliwą na średnim ogniu."),
            PreparationStep(stepNumber: 4, instruction: "Smaż kurczaka przez około 8-10 minut, aż będzie złocisty i dobrze wysmażony."),
            PreparationStep(stepNumber: 5, instruction: "Ugotuj brokuły na parze przez 5-7 minut, aby były miękkie, ale chrupiące."),
            PreparationStep(stepNumber: 6, instruction: "Ułóż w misce ryż, dodaj kurczaka i brokuły. Możesz polać sosem na bazie sosu sojowego lub naturalnym jogurtem.")
        ],
        nutrition: Nutrition(kcal: 1250, protein: 85, fat: 30, carbs: 150, fiber: 10, salt: 2)
    )

    static let pancakes = Recipe(
        name: "Placki bananowe",
        description: "Szybkie, słodkie śniadanie na bazie banana i jajka.",
        favourite: false,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 15,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Banany", amount: 2, unit: .piece),
            Ingredient(name: "Jajka", amount: 2, unit: .piece),
            Ingredient(name: "Płatki owsiane", amount: 60, unit: .gram),
            Ingredient(name: "Jogurt naturalny", amount: 100, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Rozgnieć banany widelcem na gładką masę."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj jajka i płatki owsiane do bananów, dokładnie wymieszaj."),
            PreparationStep(stepNumber: 3, instruction: "Opcjonalnie dodaj szczyptę cynamonu dla lepszego smaku."),
            PreparationStep(stepNumber: 4, instruction: "Rozgrzej patelnię na średnim ogniu (możesz użyć odrobiny masła lub oleju)."),
            PreparationStep(stepNumber: 5, instruction: "Nakładaj łyżką porcje ciasta na patelnię i smaż około 2-3 minuty z każdej strony, aż będą złociste."),
            PreparationStep(stepNumber: 6, instruction: "Podawaj z jogurtem naturalnym, owocami lub miodem.")
        ],
        nutrition: Nutrition(kcal: 700, protein: 28, fat: 18, carbs: 110, fiber: 9, salt: 1.2)
    )

    static let avocadoToast = Recipe(
        name: "Tost z awokado",
        description: "Chrupiący tost z kremowym awokado i jajkiem.",
        favourite: false,
        category: .breakfast,
        servings: 1,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1525351484163-7529414344d8?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Pieczywo tostowe", amount: 2, unit: .piece),
            Ingredient(name: "Awokado", amount: 1, unit: .piece),
            Ingredient(name: "Jajko", amount: 1, unit: .piece),
            Ingredient(name: "Sok z cytryny", amount: 5, unit: .milliliter),
            Ingredient(name: "Sól", amount: 1, unit: .teaspoon),
            Ingredient(name: "Pieprz", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Opiecz pieczywo na patelni lub w tosterze."),
            PreparationStep(stepNumber: 2, instruction: "Rozgnieć awokado z sokiem z cytryny, dopraw solą i pieprzem."),
            PreparationStep(stepNumber: 3, instruction: "Ugotuj jajko na miękko lub usmaż jajko sadzone."),
            PreparationStep(stepNumber: 4, instruction: "Posmaruj tosty awokado i dodaj jajko."),
            PreparationStep(stepNumber: 5, instruction: "Podawaj od razu.")
        ],
        nutrition: Nutrition(kcal: 450, protein: 16, fat: 28, carbs: 36, fiber: 8, salt: 1.5)
    )

    static let greekSalad = Recipe(
        name: "Sałatka grecka",
        description: "Klasyczna sałatka z fetą, oliwkami i warzywami.",
        favourite: false,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 15,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Pomidory", amount: 200, unit: .gram),
            Ingredient(name: "Ogórek", amount: 150, unit: .gram),
            Ingredient(name: "Ser feta", amount: 100, unit: .gram),
            Ingredient(name: "Oliwki", amount: 50, unit: .gram),
            Ingredient(name: "Cebula czerwona", amount: 50, unit: .gram),
            Ingredient(name: "Oliwa", amount: 20, unit: .gram),
            Ingredient(name: "Oregano", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Pokrój warzywa w większą kostkę."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj pokruszoną fetę i oliwki."),
            PreparationStep(stepNumber: 3, instruction: "Skrop oliwą i dopraw oregano."),
            PreparationStep(stepNumber: 4, instruction: "Delikatnie wymieszaj i podawaj.")
        ],
        nutrition: Nutrition(kcal: 700, protein: 22, fat: 55, carbs: 30, fiber: 8, salt: 3)
    )

    static let spaghettiBolognese = Recipe(
        name: "Spaghetti bolognese",
        description: "Makaron z sosem pomidorowym i wołowiną.",
        favourite: false,
        category: .dinner,
        servings: 4,
        prepTimeMinutes: 45,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1622973536968-3ead9e780960?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Makaron spaghetti", amount: 400, unit: .gram),
            Ingredient(name: "Mięso mielone wołowe", amount: 500, unit: .gram),
            Ingredient(name: "Passata pomidorowa", amount: 500, unit: .milliliter),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Czosnek", amount: 2, unit: .piece),
            Ingredient(name: "Oliwa", amount: 20, unit: .gram),
            Ingredient(name: "Przyprawy", amount: 2, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj makaron al dente zgodnie z instrukcją."),
            PreparationStep(stepNumber: 2, instruction: "Podsmaż cebulę i czosnek na oliwie."),
            PreparationStep(stepNumber: 3, instruction: "Dodaj mięso i smaż do zrumienienia."),
            PreparationStep(stepNumber: 4, instruction: "Wlej passatę, dopraw i duś 20–25 minut."),
            PreparationStep(stepNumber: 5, instruction: "Podawaj z makaronem." )
        ],
        nutrition: Nutrition(kcal: 2200, protein: 120, fat: 80, carbs: 260, fiber: 12, salt: 6)
    )

    static let veggieCurry = Recipe(
        name: "Warzywne curry",
        description: "Aromatyczne curry z warzywami i mlekiem kokosowym.",
        favourite: true,
        category: .dinner,
        servings: 4,
        prepTimeMinutes: 35,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1455619452474-d2be8b1e70cd?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Mleko kokosowe", amount: 400, unit: .milliliter),
            Ingredient(name: "Ciecierzyca", amount: 240, unit: .gram),
            Ingredient(name: "Warzywa mieszane", amount: 400, unit: .gram),
            Ingredient(name: "Pasta curry", amount: 40, unit: .gram),
            Ingredient(name: "Ryż basmati (suchy)", amount: 200, unit: .gram),
            Ingredient(name: "Olej", amount: 10, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Podsmaż pastę curry na oleju."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj warzywa i smaż kilka minut."),
            PreparationStep(stepNumber: 3, instruction: "Wlej mleko kokosowe i dodaj ciecierzycę."),
            PreparationStep(stepNumber: 4, instruction: "Gotuj 15–20 minut do miękkości warzyw."),
            PreparationStep(stepNumber: 5, instruction: "Podawaj z ugotowanym ryżem.")
        ],
        nutrition: Nutrition(kcal: 1900, protein: 60, fat: 90, carbs: 230, fiber: 20, salt: 5)
    )

    static let oatmealBerries = Recipe(
        name: "Owsianka z owocami",
        description: "Kremowa owsianka z bananem i jagodami.",
        favourite: false,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1517673400267-0251440c45dc?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Płatki owsiane", amount: 100, unit: .gram),
            Ingredient(name: "Mleko", amount: 300, unit: .milliliter),
            Ingredient(name: "Banan", amount: 1, unit: .piece),
            Ingredient(name: "Jagody", amount: 100, unit: .gram),
            Ingredient(name: "Miód", amount: 20, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj płatki w mleku do zgęstnienia."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj pokrojonego banana i jagody."),
            PreparationStep(stepNumber: 3, instruction: "Dosłodź miodem i podawaj ciepłe.")
        ],
        nutrition: Nutrition(kcal: 700, protein: 20, fat: 12, carbs: 130, fiber: 10, salt: 0.6)
    )

    static let chickenCaesarWrap = Recipe(
        name: "Wrap z kurczakiem Caesar",
        description: "Sycący wrap z kurczakiem, sałatą i sosem Caesar.",
        favourite: true,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 20,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Tortilla", amount: 2, unit: .piece),
            Ingredient(name: "Kurczak grillowany", amount: 200, unit: .gram),
            Ingredient(name: "Sałata rzymska", amount: 100, unit: .gram),
            Ingredient(name: "Sos Caesar", amount: 60, unit: .gram),
            Ingredient(name: "Parmezan", amount: 30, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Pokrój kurczaka w paski."),
            PreparationStep(stepNumber: 2, instruction: "Wymieszaj z sałatą, sosem i parmezanem."),
            PreparationStep(stepNumber: 3, instruction: "Zawiń farsz w tortille."),
            PreparationStep(stepNumber: 4, instruction: "Opcjonalnie podgrzej na suchej patelni.")
        ],
        nutrition: Nutrition(kcal: 1100, protein: 70, fat: 55, carbs: 90, fiber: 8, salt: 3)
    )

    static let salmonQuinoa = Recipe(
        name: "Łosoś z komosą ryżową",
        description: "Delikatny łosoś podany z komosą i brokułem.",
        favourite: false,
        category: .dinner,
        servings: 2,
        prepTimeMinutes: 30,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Łosoś", amount: 300, unit: .gram),
            Ingredient(name: "Komosa ryżowa", amount: 150, unit: .gram),
            Ingredient(name: "Brokuł", amount: 200, unit: .gram),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Cytryna", amount: 1, unit: .piece),
            Ingredient(name: "Przyprawy", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj komosę ryżową zgodnie z instrukcją."),
            PreparationStep(stepNumber: 2, instruction: "Dopraw łososia i usmaż lub upiecz na złoto."),
            PreparationStep(stepNumber: 3, instruction: "Ugotuj brokuł na parze do miękkości."),
            PreparationStep(stepNumber: 4, instruction: "Podawaj łososia z komosą i brokułem, skrop sokiem z cytryny.")
        ],
        nutrition: Nutrition(kcal: 1200, protein: 80, fat: 45, carbs: 90, fiber: 10, salt: 2)
    )

    static let lentilSoup = Recipe(
        name: "Zupa z soczewicy",
        description: "Pożywna zupa na bazie czerwonej soczewicy.",
        favourite: false,
        category: .lunch,
        servings: 4,
        prepTimeMinutes: 40,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1476718406336-bb5a9690ee2a?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Soczewica czerwona", amount: 250, unit: .gram),
            Ingredient(name: "Bulion warzywny", amount: 1, unit: .liter),
            Ingredient(name: "Marchew", amount: 150, unit: .gram),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Pomidory krojone", amount: 400, unit: .gram),
            Ingredient(name: "Przyprawy", amount: 2, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Podsmaż cebulę i marchew."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj soczewicę i wymieszaj."),
            PreparationStep(stepNumber: 3, instruction: "Zalej bulionem i dodaj pomidory."),
            PreparationStep(stepNumber: 4, instruction: "Gotuj 20–25 minut do miękkości."),
            PreparationStep(stepNumber: 5, instruction: "Dopraw do smaku i podawaj.")
        ],
        nutrition: Nutrition(kcal: 1600, protein: 80, fat: 20, carbs: 260, fiber: 30, salt: 5)
    )

    static let scrambledEggs = Recipe(
        name: "Jajecznica ze szczypiorkiem",
        description: "Puszysta jajecznica z masłem i świeżym szczypiorkiem.",
        favourite: false,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Jajka", amount: 4, unit: .piece),
            Ingredient(name: "Masło", amount: 10, unit: .gram),
            Ingredient(name: "Szczypiorek", amount: 10, unit: .gram),
            Ingredient(name: "Sól", amount: 1, unit: .teaspoon),
            Ingredient(name: "Pieprz", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Roztrzep jajka w misce."),
            PreparationStep(stepNumber: 2, instruction: "Rozpuść masło na patelni."),
            PreparationStep(stepNumber: 3, instruction: "Smaż jajka na małym ogniu, mieszając."),
            PreparationStep(stepNumber: 4, instruction: "Dodaj posiekany szczypiorek."),
            PreparationStep(stepNumber: 5, instruction: "Dopraw solą i pieprzem.")
        ],
        nutrition: Nutrition(kcal: 500, protein: 28, fat: 40, carbs: 2, fiber: 1, salt: 2)
    )

    static let beefStirFry = Recipe(
        name: "Wołowina stir-fry z warzywami",
        description: "Szybkie danie z wok’a z makaronem ryżowym.",
        favourite: false,
        category: .dinner,
        servings: 3,
        prepTimeMinutes: 25,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1512058564366-18510be2db19?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Wołowina", amount: 400, unit: .gram),
            Ingredient(name: "Papryka", amount: 200, unit: .gram),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Sos sojowy", amount: 30, unit: .milliliter),
            Ingredient(name: "Makaron ryżowy (suchy)", amount: 200, unit: .gram),
            Ingredient(name: "Olej", amount: 10, unit: .gram),
            Ingredient(name: "Czosnek", amount: 2, unit: .piece)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Rozgrzej olej na patelni lub woku."),
            PreparationStep(stepNumber: 2, instruction: "Smaż wołowinę do zrumienienia."),
            PreparationStep(stepNumber: 3, instruction: "Dodaj warzywa i smaż 3–4 minuty."),
            PreparationStep(stepNumber: 4, instruction: "Dodaj czosnek i sos sojowy, wymieszaj."),
            PreparationStep(stepNumber: 5, instruction: "Ugotuj makaron ryżowy i połącz z mięsem i warzywami.")
        ],
        nutrition: Nutrition(kcal: 1800, protein: 90, fat: 50, carbs: 230, fiber: 8, salt: 6)
    )

    static let yogurtParfait = Recipe(
        name: "Jogurt z granolą i owocami",
        description: "Warstwowy pucharek z jogurtem naturalnym, granolą i świeżymi owocami.",
        favourite: false,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1488477181946-6428a0291777?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Jogurt naturalny", amount: 300, unit: .gram),
            Ingredient(name: "Granola", amount: 80, unit: .gram),
            Ingredient(name: "Truskawki", amount: 150, unit: .gram),
            Ingredient(name: "Miód", amount: 20, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Do pucharków nałóż warstwę jogurtu, następnie granolę i truskawki."),
            PreparationStep(stepNumber: 2, instruction: "Powtórz warstwy i polej miodem."),
            PreparationStep(stepNumber: 3, instruction: "Podawaj od razu.")
        ],
        nutrition: Nutrition(kcal: 800, protein: 30, fat: 20, carbs: 120, fiber: 6, salt: 0.6)
    )

    static let chiaPudding = Recipe(
        name: "Pudding chia z mlekiem i owocami",
        description: "Lekki pudding z nasion chia, mleka i owoców.",
        favourite: false,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1546548970-71785318a17b?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Nasiona chia", amount: 60, unit: .gram),
            Ingredient(name: "Mleko", amount: 400, unit: .milliliter),
            Ingredient(name: "Miód", amount: 20, unit: .gram),
            Ingredient(name: "Maliny", amount: 100, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Wymieszaj nasiona chia z mlekiem i miodem."),
            PreparationStep(stepNumber: 2, instruction: "Odstaw na minimum 20 minut lub na noc do lodówki."),
            PreparationStep(stepNumber: 3, instruction: "Podawaj z malinami.")
        ],
        nutrition: Nutrition(kcal: 700, protein: 20, fat: 30, carbs: 70, fiber: 15, salt: 0.4)
    )

    static let frenchToast = Recipe(
        name: "Tosty francuskie",
        description: "Słodkie tosty w jajku z cynamonem i owocami.",
        favourite: false,
        category: .breakfast,
        servings: 2,
        prepTimeMinutes: 15,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Pieczywo tostowe", amount: 4, unit: .piece),
            Ingredient(name: "Jajka", amount: 2, unit: .piece),
            Ingredient(name: "Mleko", amount: 100, unit: .milliliter),
            Ingredient(name: "Masło", amount: 10, unit: .gram),
            Ingredient(name: "Cynamon", amount: 1, unit: .teaspoon),
            Ingredient(name: "Truskawki", amount: 100, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Roztrzep jajka z mlekiem i cynamonem."),
            PreparationStep(stepNumber: 2, instruction: "Mocz kromki pieczywa w mieszance."),
            PreparationStep(stepNumber: 3, instruction: "Smaż na maśle po 2–3 minuty z każdej strony."),
            PreparationStep(stepNumber: 4, instruction: "Podawaj z owocami.")
        ],
        nutrition: Nutrition(kcal: 900, protein: 28, fat: 35, carbs: 110, fiber: 5, salt: 1.5)
    )

    static let smoothieBowl = Recipe(
        name: "Smoothie bowl",
        description: "Gęsty koktajl w misce z dodatkami.",
        favourite: false,
        category: .breakfast,
        servings: 1,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1590301157890-4810ed352733?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Banan", amount: 1, unit: .piece),
            Ingredient(name: "Mrożone owoce", amount: 150, unit: .gram),
            Ingredient(name: "Mleko", amount: 150, unit: .milliliter),
            Ingredient(name: "Płatki owsiane", amount: 30, unit: .gram),
            Ingredient(name: "Masło orzechowe", amount: 15, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Zmiksuj banana, owoce i mleko na gęsty koktajl."),
            PreparationStep(stepNumber: 2, instruction: "Przelej do miski i posyp płatkami oraz masłem orzechowym.")
        ],
        nutrition: Nutrition(kcal: 600, protein: 12, fat: 18, carbs: 95, fiber: 8, salt: 0.5)
    )

    static let cottageCheeseBowl = Recipe(
        name: "Twaróg z owocami i miodem",
        description: "Białkowe śniadanie z twarogiem, owocami i miodem.",
        favourite: false,
        category: .breakfast,
        servings: 1,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1495214783159-3503fd1b572d?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Twaróg półtłusty", amount: 200, unit: .gram),
            Ingredient(name: "Jogurt naturalny", amount: 50, unit: .gram),
            Ingredient(name: "Miód", amount: 15, unit: .gram),
            Ingredient(name: "Borówki", amount: 100, unit: .gram),
            Ingredient(name: "Orzechy włoskie", amount: 20, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Wymieszaj twaróg z jogurtem i miodem."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj owoce i posyp orzechami."),
            PreparationStep(stepNumber: 3, instruction: "Podawaj od razu.")
        ],
        nutrition: Nutrition(kcal: 500, protein: 35, fat: 20, carbs: 35, fiber: 4, salt: 0.8)
    )

    static let tunaSalad = Recipe(
        name: "Sałatka z tuńczykiem",
        description: "Lekka sałatka z tuńczykiem, kukurydzą i jajkiem.",
        favourite: false,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 15,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Tuńczyk w sosie własnym", amount: 160, unit: .gram),
            Ingredient(name: "Kukurydza", amount: 150, unit: .gram),
            Ingredient(name: "Jajka", amount: 2, unit: .piece),
            Ingredient(name: "Sałata", amount: 100, unit: .gram),
            Ingredient(name: "Cebula czerwona", amount: 50, unit: .gram),
            Ingredient(name: "Oliwa", amount: 15, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj jajka na twardo i pokrój."),
            PreparationStep(stepNumber: 2, instruction: "Wymieszaj tuńczyka, kukurydzę, sałatę i cebulę."),
            PreparationStep(stepNumber: 3, instruction: "Dodaj jajka i skrop oliwą. Dopraw solą i pieprzem.")
        ],
        nutrition: Nutrition(kcal: 800, protein: 45, fat: 35, carbs: 50, fiber: 6, salt: 2.5)
    )

    static let quinoaVeggieBowl = Recipe(
        name: "Miska z komosą i warzywami",
        description: "Pożywna miska z komosą, warzywami i sosem.",
        favourite: false,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 25,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Komosa ryżowa", amount: 150, unit: .gram),
            Ingredient(name: "Warzywa mieszane", amount: 300, unit: .gram),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Sos sojowy", amount: 15, unit: .milliliter),
            Ingredient(name: "Pestki dyni", amount: 20, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj komosę zgodnie z instrukcją."),
            PreparationStep(stepNumber: 2, instruction: "Podsmaż warzywa na oliwie."),
            PreparationStep(stepNumber: 3, instruction: "Wymieszaj z komosą, sosem sojowym i pestkami.")
        ],
        nutrition: Nutrition(kcal: 1000, protein: 35, fat: 28, carbs: 150, fiber: 12, salt: 3)
    )

    static let capreseSandwich = Recipe(
        name: "Kanapka caprese",
        description: "Kanapka z mozzarellą, pomidorem i bazylią.",
        favourite: false,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1592417817098-8fd3d9eb14a5?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Bułka pełnoziarnista", amount: 2, unit: .piece),
            Ingredient(name: "Mozzarella", amount: 125, unit: .gram),
            Ingredient(name: "Pomidory", amount: 150, unit: .gram),
            Ingredient(name: "Bazylia", amount: 10, unit: .gram),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Przekrój bułki i skrop oliwą."),
            PreparationStep(stepNumber: 2, instruction: "Ułóż plastry mozzarelli i pomidora, dodaj bazylię."),
            PreparationStep(stepNumber: 3, instruction: "Podawaj na świeżo lub podgrzej w opiekaczu.")
        ],
        nutrition: Nutrition(kcal: 700, protein: 30, fat: 30, carbs: 80, fiber: 6, salt: 2)
    )

    static let chickenSoup = Recipe(
        name: "Rosół domowy",
        description: "Aromatyczna zupa drobiowa z makaronem.",
        favourite: false,
        category: .lunch,
        servings: 4,
        prepTimeMinutes: 60,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1594756202469-9ff9799b2e4e?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Kurczak (skrzydła/udo)", amount: 400, unit: .gram),
            Ingredient(name: "Marchew", amount: 150, unit: .gram),
            Ingredient(name: "Seler", amount: 100, unit: .gram),
            Ingredient(name: "Pietruszka (korzeń)", amount: 100, unit: .gram),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Makaron", amount: 200, unit: .gram),
            Ingredient(name: "Przyprawy", amount: 2, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Zalej kurczaka wodą i zagotuj, zbierz szumowiny."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj warzywa i gotuj na małym ogniu 45 minut."),
            PreparationStep(stepNumber: 3, instruction: "Ugotuj makaron osobno."),
            PreparationStep(stepNumber: 4, instruction: "Dopraw i podawaj z makaronem.")
        ],
        nutrition: Nutrition(kcal: 1600, protein: 90, fat: 50, carbs: 170, fiber: 8, salt: 6)
    )

    static let hummusPlate = Recipe(
        name: "Talerz z hummusem i warzywami",
        description: "Szybki lunch z hummusem, warzywami i pitą.",
        favourite: false,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 10,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1577805947697-89e18249d767?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Hummus", amount: 200, unit: .gram),
            Ingredient(name: "Warzywa świeże", amount: 300, unit: .gram),
            Ingredient(name: "Chleb pita", amount: 2, unit: .piece),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Papryka słodka", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Rozsmaruj hummus na talerzu i skrop oliwą."),
            PreparationStep(stepNumber: 2, instruction: "Podaj z pokrojonymi warzywami i pitą."),
            PreparationStep(stepNumber: 3, instruction: "Posyp papryką.")
        ],
        nutrition: Nutrition(kcal: 900, protein: 30, fat: 40, carbs: 110, fiber: 16, salt: 3)
    )

    static let riceAndBeans = Recipe(
        name: "Ryż z fasolą",
        description: "Proste danie z ryżem, czarną fasolą i przyprawami.",
        favourite: false,
        category: .lunch,
        servings: 2,
        prepTimeMinutes: 25,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1536304929831-ee1ca9d44906?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Ryż biały (suchy)", amount: 150, unit: .gram),
            Ingredient(name: "Fasola czarna (ugotowana)", amount: 240, unit: .gram),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Olej", amount: 10, unit: .gram),
            Ingredient(name: "Przyprawy", amount: 2, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj ryż."),
            PreparationStep(stepNumber: 2, instruction: "Podsmaż cebulę na oleju, dodaj fasolę i przyprawy."),
            PreparationStep(stepNumber: 3, instruction: "Wymieszaj z ryżem i podawaj.")
        ],
        nutrition: Nutrition(kcal: 1100, protein: 30, fat: 20, carbs: 200, fiber: 16, salt: 4)
    )

    static let turkeyMeatballs = Recipe(
        name: "Pulpety z indyka w sosie pomidorowym",
        description: "Delikatne pulpety z indyka duszone w sosie pomidorowym, podawane z ryżem.",
        favourite: false,
        category: .dinner,
        servings: 3,
        prepTimeMinutes: 35,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1529042410759-befb1204b468?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Mięso mielone z indyka", amount: 500, unit: .gram),
            Ingredient(name: "Ryż (suchy)", amount: 150, unit: .gram),
            Ingredient(name: "Passata pomidorowa", amount: 400, unit: .milliliter),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Czosnek", amount: 2, unit: .piece),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Przyprawy", amount: 2, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Uformuj małe pulpety z doprawionego mięsa."),
            PreparationStep(stepNumber: 2, instruction: "Obsmaż na oliwie do zrumienienia."),
            PreparationStep(stepNumber: 3, instruction: "Dodaj passatę, cebulę i czosnek, duś 15–20 minut."),
            PreparationStep(stepNumber: 4, instruction: "Ugotuj ryż i podawaj z sosem.")
        ],
        nutrition: Nutrition(kcal: 2000, protein: 110, fat: 60, carbs: 180, fiber: 8, salt: 6)
    )

    static let shrimpPasta = Recipe(
        name: "Makaron z krewetkami i czosnkiem",
        description: "Kremowy makaron z krewetkami, czosnkiem i pietruszką.",
        favourite: false,
        category: .dinner,
        servings: 2,
        prepTimeMinutes: 25,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1563379926898-05f4575a45d8?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Makaron spaghetti", amount: 200, unit: .gram),
            Ingredient(name: "Krewetki", amount: 250, unit: .gram),
            Ingredient(name: "Czosnek", amount: 2, unit: .piece),
            Ingredient(name: "Oliwa", amount: 20, unit: .gram),
            Ingredient(name: "Śmietanka", amount: 100, unit: .milliliter),
            Ingredient(name: "Natka pietruszki", amount: 10, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj makaron al dente."),
            PreparationStep(stepNumber: 2, instruction: "Podsmaż czosnek na oliwie, dodaj krewetki."),
            PreparationStep(stepNumber: 3, instruction: "Wlej śmietankę, dodaj pietruszkę i wymieszaj."),
            PreparationStep(stepNumber: 4, instruction: "Połącz z makaronem i podawaj.")
        ],
        nutrition: Nutrition(kcal: 1500, protein: 70, fat: 60, carbs: 160, fiber: 4, salt: 4)
    )

    static let mushroomRisotto = Recipe(
        name: "Risotto z pieczarkami",
        description: "Kremowe risotto z pieczarkami i parmezanem.",
        favourite: false,
        category: .dinner,
        servings: 3,
        prepTimeMinutes: 35,
        difficulty: .medium,
        imageURL: URL(string: "https://images.unsplash.com/photo-1476124369491-e7addf5db371?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Ryż arborio", amount: 300, unit: .gram),
            Ingredient(name: "Bulion warzywny", amount: 1, unit: .liter),
            Ingredient(name: "Pieczarki", amount: 300, unit: .gram),
            Ingredient(name: "Cebula", amount: 100, unit: .gram),
            Ingredient(name: "Parmezan", amount: 40, unit: .gram),
            Ingredient(name: "Masło", amount: 20, unit: .gram),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Białe wino", amount: 100, unit: .milliliter)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Podsmaż cebulę na oliwie i maśle."),
            PreparationStep(stepNumber: 2, instruction: "Dodaj ryż i chwilę podsmaż."),
            PreparationStep(stepNumber: 3, instruction: "Stopniowo dolewaj bulion, mieszając, aż ryż będzie kremowy."),
            PreparationStep(stepNumber: 4, instruction: "Dodaj podsmażone pieczarki i parmezan.")
        ],
        nutrition: Nutrition(kcal: 2100, protein: 45, fat: 60, carbs: 320, fiber: 8, salt: 4)
    )

    static let tofuTeriyaki = Recipe(
        name: "Tofu teriyaki z ryżem",
        description: "Smażone tofu z brokułem w sosie teriyaki, podawane z ryżem.",
        favourite: false,
        category: .dinner,
        servings: 2,
        prepTimeMinutes: 25,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1564834724105-918b73d1b9e0?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Tofu", amount: 300, unit: .gram),
            Ingredient(name: "Sos teriyaki", amount: 60, unit: .milliliter),
            Ingredient(name: "Brokuł", amount: 200, unit: .gram),
            Ingredient(name: "Ryż (suchy)", amount: 150, unit: .gram),
            Ingredient(name: "Olej", amount: 10, unit: .gram),
            Ingredient(name: "Sezam", amount: 10, unit: .gram)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Ugotuj ryż."),
            PreparationStep(stepNumber: 2, instruction: "Podsmaż tofu na oleju do zarumienienia."),
            PreparationStep(stepNumber: 3, instruction: "Dodaj brokuł i sos teriyaki, duś kilka minut."),
            PreparationStep(stepNumber: 4, instruction: "Podawaj z ryżem, posyp sezamem.")
        ],
        nutrition: Nutrition(kcal: 1400, protein: 55, fat: 35, carbs: 200, fiber: 10, salt: 4)
    )

    static let bakedPotatoesCottage = Recipe(
        name: "Pieczone ziemniaki z twarogiem",
        description: "Ziemniaki pieczone w skórce z kremowym twarogiem i szczypiorkiem.",
        favourite: false,
        category: .dinner,
        servings: 2,
        prepTimeMinutes: 45,
        difficulty: .easy,
        imageURL: URL(string: "https://images.unsplash.com/photo-1568569350062-ebfa3cb195df?w=800&q=80"),
        ingredients: [
            Ingredient(name: "Ziemniaki", amount: 600, unit: .gram),
            Ingredient(name: "Twaróg półtłusty", amount: 200, unit: .gram),
            Ingredient(name: "Jogurt naturalny", amount: 100, unit: .gram),
            Ingredient(name: "Szczypiorek", amount: 10, unit: .gram),
            Ingredient(name: "Oliwa", amount: 10, unit: .gram),
            Ingredient(name: "Sól", amount: 1, unit: .teaspoon)
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Umyj ziemniaki, nakłuj i piecz 40–50 minut w 200°C."),
            PreparationStep(stepNumber: 2, instruction: "Wymieszaj twaróg z jogurtem i szczypiorkiem."),
            PreparationStep(stepNumber: 3, instruction: "Nacięte ziemniaki skrop oliwą i nadziej twarogiem.")
        ],
        nutrition: Nutrition(kcal: 1200, protein: 40, fat: 25, carbs: 200, fiber: 12, salt: 3)
    )

    static let all: [Recipe] = [
        omelette,
        tomatoSoup,
        chickenBowl,
        pancakes,
        avocadoToast,
        greekSalad,
        spaghettiBolognese,
        veggieCurry,
        oatmealBerries,
        chickenCaesarWrap,
        salmonQuinoa,
        lentilSoup,
        scrambledEggs,
        beefStirFry,
        yogurtParfait,
        chiaPudding,
        frenchToast,
        smoothieBowl,
        cottageCheeseBowl,
        tunaSalad,
        quinoaVeggieBowl,
        capreseSandwich,
        chickenSoup,
        hummusPlate,
        riceAndBeans,
        turkeyMeatballs,
        shrimpPasta,
        mushroomRisotto,
        tofuTeriyaki,
        bakedPotatoesCottage
    ]
}

