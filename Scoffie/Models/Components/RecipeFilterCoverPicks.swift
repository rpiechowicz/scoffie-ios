import Foundation

/// Zdjęcia opcji filtrów wybrane RĘCZNIE (6.10.2026, Rafał: „zmień zdjęcia
/// posiłków na takie, które będą bardziej pasować”). Automat
/// (`RecipeCoverPicker`) brał pierwszy pasujący przepis z puli, więc „Ryż
/// i kasze” potrafiło pokazać kaszę na słodko, a „Zupy” — miskę, której nie
/// dało się rozpoznać w kółku 60 pt. Tu stoi po dwa przepisy na opcję,
/// wybrane z arkuszy miniatur całego katalogu: pierwszy — najczytelniejszy
/// w małym kółku, drugi — zapas (zwykle bez mięsa), gdy pierwszy ukrywa
/// dieta albo alergeny z profilu. Gdy żadnego nie ma w puli, wraca automat.
///
/// Klucz: „rodzaj:kategoria:opcja” (`dish:lunch:soup`, `taste:breakfast:sweet`,
/// `protein:dinner:fish`, `slot:snacks:afternoonSnack`) albo — kafelki
/// podstron wszystkich przepisów — „cuisine:KUCHNIA”, „diet:dieta”,
/// „trait:cecha”, „moment:OKAZJA” (wartości `rawValue`). Podstrony doszły
/// wieczorem 6.10.2026; „Ulubione” i „Thermomix” zostają przy automacie
/// (ulubione każdy dom ma inne). Wartość: id przepisów katalogu — ten sam
/// UUID co nazwa pliku zdjęcia w `img.scoffie.app/recipe-images/`, więc wybór
/// trafia także wtedy, gdy przepis dostał nowe zdjęcie (zmienia się tylko
/// końcówka nazwy). Nowy przepis albo zdjęcie lepsze od wybranego = zmiana
/// tutaj.
enum RecipeFilterCoverPicks {
    static func ids(_ key: String) -> [String] {
        byKey[key] ?? []
    }

    static func key(_ kind: RecipeFacetKind, in category: RecipesCategory, option: String) -> String? {
        let name: String
        switch category {
        case .breakfast: name = "breakfast"
        case .lunch:     name = "lunch"
        case .dinner:    name = "dinner"
        case .snacks:    name = "snacks"
        case .all, .favourite: return nil
        }
        return "\(kind.rawValue):\(name):\(option)"
    }

    private static let byKey: [String: [String]] = [
        // Owsianka z bananem i borówką · Owsianka z twarogiem i jagodami
        "dish:breakfast:porridge": ["9e845247-f630-4dcc-9bab-3656828cac29", "ef43e241-0aa0-48db-942e-f8b603652928"],
        // Jajecznica z awokado i pomidorem · Jajecznica na boczku
        "dish:breakfast:eggs": ["168d56ab-a650-4b99-9738-c4baf5ceee42", "b86069af-8018-4c38-bf3c-2b5f36e6c49a"],
        // Kanapki z szynką, serem i pomidorem · Kanapka z twarożkiem i ogórkiem
        "dish:breakfast:bread": ["4b5c9b22-d219-4719-82be-dc25b22fef52", "6493a2b1-6e89-487e-9f15-084e2d8e8355"],
        // Naleśniki z twarożkiem i truskawkami · Naleśniki wegańskie z masłem orzechowym i truskawkami
        "dish:breakfast:pancakes": ["dfc56004-caed-4202-b92b-3c01122b694c", "0daf9e01-0aad-4f36-a969-bb72813523b8"],
        // Jogurt naturalny z musli, truskawkami i borówkami · Parfait jogurtowe z musem truskawkowym i granolą
        "dish:breakfast:yogurt": ["d0d09af3-1821-47be-be95-63a208fc47bd", "2c967a54-95ae-4e7d-9659-fe7f6f2d86e6"],
        // Zupa pomidorowa z ryżem · Zupa koperkowa z ryżem
        "dish:lunch:soup": ["2047e0d9-0aba-4877-8191-c222efd3d5eb", "3a0f86c2-ce28-4147-872a-4e4d248aa45a"],
        // Pieczone udka z ziemniakami · Gzik z ziemniakami
        "dish:lunch:potatoes": ["1557db6b-f40f-4366-adc1-db338cdcd90f", "dcbe3b36-dfff-41a6-b946-493ad77355d4"],
        // Ryż z kurczakiem i papryką · Chrupiące tofu z ryżem i warzywami
        "dish:lunch:grains": ["42ced396-7ea3-4719-baab-d7fc2c2c614b", "7f006b33-12ae-4b8c-94b2-27d8eb6aa7fb"],
        // Spaghetti z sosem pomidorowym i mięsem · Spaghetti carbonara
        "dish:lunch:pasta": ["10ad7ca1-2172-4e20-811c-0e95f2d53692", "8dc245ab-82f3-4a20-90d8-d8afa6c2c03b"],
        // Pierogi ruskie z okrasą cebulową · Pierogi z kapustą i grzybami
        "dish:lunch:dumplings": ["2b63c5bd-e52b-4fe1-af0f-7883ef6b9066", "e467a224-f393-41cd-82a2-b197cab26543"],
        // Gulasz wieprzowy z kaszą gryczaną i ogórkiem kiszonym · Gulasz z grzybów leśnych z kaszą gryczaną
        "dish:lunch:stew": ["d5885b80-59b5-4063-a63f-06b8493410bc", "b98cf05c-2571-490e-8445-cb025005dbc5"],
        // Zapiekanka pasterska z mieloną wołowiną · Lasagne ze szpinakiem i ricottą
        "dish:lunch:bake": ["94aa009a-6cfc-4285-8f55-94016cb7491e", "66cec364-1ef7-4dbc-aada-543bddf5eba4"],
        // Burgery wołowe z frytkami · Burgery z ciecierzycy z frytkami z batatów
        "dish:lunch:sandwich": ["b6967ae5-0885-43a3-a5a0-4f0aa022e9d2", "7c9d6a7f-a66a-40cb-8c29-3a683b59c6ea"],
        // Sałatka caprese z awokado · Sałatka grecka z pieczywem
        "dish:dinner:salad": ["dba8974d-714a-4e0e-8dfe-af28d8655413", "771d5a65-dc3b-4f29-a23f-46084875f1c5"],
        // Kanapka klubowa z kurczakiem i boczkiem · Kanapki na ciepło z mozzarellą i pomidorem
        "dish:dinner:sandwich": ["3f3301ee-6f53-4c6f-92c6-ab38642a31e1", "9afe1a2b-4f90-4772-801b-624c592d97ad"],
        // Domowa pizza margherita · Pizza capricciosa
        "dish:dinner:bake": ["17fc1606-231c-41d3-b4ca-2e7ab042eccc", "5c8bc7bc-cade-4868-a8c8-8195001b8020"],
        // Makaron z pieczoną fetą i pomidorkami · Makaron z groszkiem i boczkiem
        "dish:dinner:grains": ["41f0a183-2d61-45a2-aabd-4c333126df89", "f90e5683-d07f-4aec-94b6-3afc9549f416"],
        // Młode ziemniaki z koperkiem i kefirem · Ziemniaki z grilla w folii z twarożkiem
        "dish:dinner:potatoes": ["654990f5-5d8d-42f5-bad0-f444b762b010", "67a13cf1-f764-4dab-93ca-7ec233f20998"],
        // Krem z pieczarek z grzankami · Krem z pomidorów z grzankami
        "dish:dinner:soup": ["08c227bb-672a-43d0-80af-8de69ef65bba", "9a745133-a07e-4489-a345-b2e59e8968d0"],
        // Placki ziemniaczane z sosem grzybowym · Naleśniki ze szpinakiem i serem
        "dish:dinner:pancakes": ["f80d6ac9-c499-4bb0-b657-d0822a0ffd13", "fa523dda-0b67-41d5-abd5-c0aa663be305"],
        // Ciasto jogurtowe z borówkami · Ciasto dyniowe z cynamonem
        "dish:snacks:bake": ["b6c4b3d6-4d09-4281-a60a-074a877d9d01", "2b6ad17a-4087-4038-b4f6-2a1c5f0467d9"],
        // Deser z galaretką, bitą śmietaną i owocami · Pudding chia na mleku z malinami
        "dish:snacks:spoon": ["f53b0816-0efb-4e4e-85b3-d95c5588af59", "76954d2c-7eb0-4c20-9c2a-d24befe049e7"],
        // Chipsy z batata z papryką · Chipsy z marchewki i pietruszki
        "dish:snacks:crunchy": ["541ea46a-01a5-42f2-8614-f765871cfb11", "6f6207d8-a787-4b75-a1e1-9eee28f7cbbd"],
        // Koreczki z mozzarellą, pomidorkami i bazylią · Koreczki z serem, szynką i ogórkiem
        "dish:snacks:bites": ["27f27ee6-67e9-490f-bd7b-be9241c167b1", "25bf4a6a-df6f-4642-83c2-1c6f5e1bcb76"],
        // Hummus z warzywami do maczania · Hummus z pieczonej dyni z warzywami
        "dish:snacks:dip": ["671cd8e4-acdc-4842-b34f-02ec33be5f8f", "e2668b2a-0c01-431c-8f96-2130b1b6f366"],
        // Sałatka z arbuzem, fetą i miętą · Sałatka owocowa z miętą i limonką
        "dish:snacks:salad": ["b6aa154a-f618-44bd-ab43-dd125f32f9d8", "ad6273f7-86cd-47d0-b69b-6b333bc47207"],
        // Koktajl malinowy z maślanką · Koktajl morelowy ze skyrem
        "dish:snacks:drink": ["b8067241-ff02-4049-ab40-4dd2951311a7", "a0c96c5b-2146-47c7-8435-1a69add45145"],
        // Owsianka czekoladowa z wiśniami · Naleśniki wegańskie z masłem orzechowym i truskawkami
        "taste:breakfast:sweet": ["4d4c70a6-fb9e-4741-b236-ea9c4e22de1e", "0daf9e01-0aad-4f36-a969-bb72813523b8"],
        // Szakszuka z papryką i cebulą · Jajecznica na boczku
        "taste:breakfast:savory": ["24a81d51-40e7-403b-92f4-cdc0f5a8426e", "b86069af-8018-4c38-bf3c-2b5f36e6c49a"],
        // Czekoladowe ciasto z kubka · Owsianka nocna z kakao i wiśniami w słoiku
        "taste:snacks:sweet": ["59e1e8fe-818b-4dc8-8e7c-ef0a18c751a9", "8f7e8ea8-57dc-4058-9d62-45f802ceb04d"],
        // Kanapka z tofu, awokado i kiełkami · Kanapka z pieczoną papryką, hummusem i rukolą
        "taste:snacks:savory": ["70036e67-1662-466f-8302-b1f4f6dadd2f", "57c1016d-5029-4720-b5f4-1060f64b0471"],
        // Pierogi ruskie z okrasą cebulową · Pierogi z kapustą i grzybami
        "cuisine:POLISH": ["2b63c5bd-e52b-4fe1-af0f-7883ef6b9066", "e467a224-f393-41cd-82a2-b197cab26543"],
        // Spaghetti carbonara · Spaghetti z sosem pomidorowym i mięsem
        "cuisine:ITALIAN": ["8dc245ab-82f3-4a20-90d8-d8afa6c2c03b", "10ad7ca1-2172-4e20-811c-0e95f2d53692"],
        // Paella z krewetkami i kurczakiem · Paella warzywna z ciecierzycą
        "cuisine:SPANISH": ["ad93575d-abc1-476f-8252-86a799e1e8eb", "48c55eb4-b7f8-49a5-bc0d-aa89a4d00aff"],
        // Sałatka grecka z pieczywem · Pita z kurczakiem gyros i warzywami
        "cuisine:GREEK": ["771d5a65-dc3b-4f29-a23f-46084875f1c5", "64328752-781f-4cd9-b4e9-3d56052ea690"],
        // Butter chicken z ryżem basmati · Kurczak tikka masala z ryżem
        "cuisine:INDIAN": ["10804db0-e7f7-4d10-a64c-2ee95e7dc052", "a431d59c-7cb7-4562-ba5b-d4138c5606e9"],
        // Pad thai z krewetkami · Zielone curry z kurczakiem
        "cuisine:THAI": ["194ede11-8c59-44d2-abe2-fc79737089e9", "958529a2-5afe-4dd7-a99b-1f309f8cd3b1"],
        // Tacos z mieloną wołowiną i serem · Tacos z mielonym indykiem
        "cuisine:MEXICAN": ["78d01993-b5e4-46b9-8f1c-69becd2ebf2a", "d810fe60-e0f6-423d-8ca5-8c53ceaeb646"],
        // Burgery wołowe z frytkami · Burgery z czerwonej fasoli
        "cuisine:AMERICAN": ["b6967ae5-0885-43a3-a5a0-4f0aa022e9d2", "f8e2e53a-0bbe-41b6-aea5-c073830d9dc9"],
        // — Diety (podstrona „Dieta”) —
        // Halloumi z pieczonymi warzywami · Gnocchi z warzywami i pesto
        "diet:vegetarian": ["f2b0e3a1-f195-4ab4-9d06-d5e3535ac957", "d6c5944f-3c31-4311-9651-d9cdbe3acaeb"],
        // Kalafior w czerwonym curry po tajsku · Curry z soczewicą i batatem
        "diet:vegan": ["2d24cab8-b48b-4a33-9d74-7ade8789e753", "c0a1abc9-861a-4e22-8068-a3d4f1b84c9f"],
        // Łosoś z batatami i fasolką · Łosoś z warzywami z jednej blachy
        "diet:withFish": ["34d8d9ac-675e-4bdf-9a20-2e2e497f9ea1", "ef87d51d-3b44-448b-99ee-4603958cc558"],
        // Risotto z pieczarkami i parmezanem · Risotto ze szparagami i groszkiem
        "diet:glutenFree": ["c3859fc1-0d1e-4f92-888f-9fdc99a6c014", "24ff075d-cb1c-4d7d-a354-0ba438429a83"],
        // Stir-fry z tofu, brokułem i papryką z ryżem jaśminowym · Dorsz w sosie curry z ryżem
        "diet:lactoseFree": ["2e500ad6-49fc-4d15-bc65-096f072f0c40", "ca9ed6ca-cb13-441f-8b09-1e3509ec6211"],
        // Jajka sadzone z awokado i wędzonym łososiem · Łosoś z sosem koperkowym i szparagami
        "diet:keto": ["59cb545d-5946-40d4-89aa-d98777fc5229", "21c8dadf-e8a0-4ed9-8719-71885d2752e4"],
        // — Cechy —
        // Kurczak tandoori z ryżem · Kurczak kung pao z ryżem
        "trait:highProtein": ["03d086e7-5505-48fb-a347-13f4a1f02146", "85725c62-604e-44ba-aae7-6448b8c1de3c"],
        // Zimowa sałatka owocowa z pomarańczą, granatem i kiwi · Twarożek z truskawkami i bazylią
        "trait:lowFat": ["d7b9250a-fdbd-4e7c-ad5c-4a9e36247b53", "2fe82da2-7c32-4193-a57c-f6b6237668ba"],
        // Fasola z tuńczykiem po toskańsku · Minestrone z fasolą i makaronem
        "trait:highFiber": ["324d5642-2a12-4b4e-93ef-392eeb547067", "ca1deebc-60e7-49e8-9789-ddbfa5f57b49"],
        // Owsianka nocna z malinami i porzeczkami · Owsianka ze skyrem i truskawkami
        "trait:lowSalt": ["63891816-8a91-46d7-bf3f-09b74bbbbbc0", "5f76f54b-9aaa-4e80-95b6-24aecb551a78"],
        // Frytki z przyprawą paprykową · Skrzydełka BBQ z coleslawem
        "trait:airfryer": ["e87756b2-7cbb-4411-a509-c231230eb7bf", "225f4275-1d99-42cf-85cd-bbdea8bb1244"],
        // Sałatka z kaszą gryczaną i fetą · Sałatka gyros warstwowa
        "trait:lunchbox": ["5183182a-8815-4f50-b027-c26ef92a7954", "0be5ef3c-8441-4891-9975-df702d4a8a3f"],
        // — Okazje i sezon —
        // Barszcz czerwony z uszkami z grzybami · Karp pieczony z ziołami
        "moment:CHRISTMAS_EVE": ["dd18ccbd-4c63-4bfc-8f95-cbc35dc2f0c6", "51f2f35b-ae40-4e32-a335-6429bed7178e"],
        // Makowiec zawijany · Piernik staropolski dojrzewający
        "moment:CHRISTMAS": ["524e32fb-16d7-402b-806b-67465b6ade3b", "53961e99-650f-4e17-9772-6966a0a64887"],
        // Klasyczne jajka faszerowane z musztardą · Mazurek kajmakowy
        "moment:EASTER": ["83eb317e-3896-45d1-a00d-217eb1253895", "212e2e53-f98e-4182-ad4c-51ea83eaca6c"],
        // Szaszłyki z kurczaka i warzyw z grilla · Szaszłyki z tofu i warzyw z grilla
        "moment:BARBECUE": ["435bfc51-8c98-42f8-bff0-c57f79f6ab26", "af7b9807-a526-4012-b4a4-f1e3eb7bcd2b"],
        // Mini burgery z wołowiną · Guacamole z nachosami
        "moment:PARTY": ["b1824f70-40d9-4368-87dc-a96e8bc0c4ce", "430a0f51-db80-4a0b-b063-dbdb7f0357d9"],
        // Szparagi z jajkiem w koszulce i sosem holenderskim · Sałatka z młodych ziemniaków, szparagów i rzodkiewki
        "moment:SPRING": ["fb492934-52e1-488c-a222-057a8faab89e", "8052e601-b379-476a-be04-c5f9da272414"],
        // Tarta z truskawkami i kremem · Chłodnik ogórkowy z jogurtem i koperkiem
        "moment:SUMMER": ["a4511cfd-a796-476a-81e3-bf8035503b2d", "a6b68a5c-e13c-4c7a-9bea-589f7957e775"],
        // Zupa krem z dyni z imbirem · Risotto z dynią i parmezanem
        "moment:AUTUMN": ["d9d70d17-3b62-4dec-b8f9-810091f7e93c", "793a0573-f8ae-4f75-8726-4753a0101993"],
        // Pieczeń wieprzowa z kapustą kiszoną · Bigos wegetariański z grzybami
        "moment:WINTER": ["d2ffabb6-2f84-446d-a2d9-c44f765a10f6", "c04dd3b6-94f9-4e95-9618-e0f924aee83f"],
        // — Mięso i ryby w obiadach i kolacjach —
        // Udka z kurczaka z ziemniakami · Kurczak tikka z sałatką z ogórka
        "protein:lunch:poultry": ["f1815824-68ee-4109-8f07-7cacbffb57bb", "d78d647c-e98d-44bc-a3a5-742a3016126f"],
        // Kotlet schabowy z ziemniakami i mizerią · Karkówka z grilla z sałatką z ogórka
        "protein:lunch:pork": ["669d9bd0-6ded-4006-b281-5299d0f3dff9", "d7bde0c0-1c76-4201-9264-0be6b8c5a9ee"],
        // Stek wołowy z frytkami z piekarnika i sałatą · Stek z masłem ziołowym i pieczarkami
        "protein:lunch:beef": ["dc2732be-1468-4156-a444-44996054dceb", "46810e92-4873-4e3b-b138-01532d520194"],
        // Łosoś z masłem czosnkowym i brokułem · Łosoś pieczony z pesto i ziemniakami
        "protein:lunch:fish": ["1fb1bba3-e0be-4f01-b5ff-9b2feb2bd3f7", "875ceb0d-449d-4320-bd5a-dd283b0cf2a6"],
        // Pieczone warzywa korzeniowe z kaszą i jajkiem · Gnocchi z warzywami i pesto
        "protein:lunch:veg": ["fd0c90b1-18f6-43d7-bbae-8d2a493d3aa3", "d6c5944f-3c31-4311-9651-d9cdbe3acaeb"],
        // Kurczak cajun z kolbą kukurydzy · Wrap z kurczakiem cezar
        "protein:dinner:poultry": ["6211faf6-421b-4abd-81e5-b11d1f3fa112", "09af8f56-2b33-4c55-b867-ebb2aa3fd4f6"],
        // Biała kiełbasa z grilla z chrzanem · Pulled pork w bułce z coleslawem
        "protein:dinner:pork": ["696c4335-63ac-49da-83b8-be9a26a1a9ea", "2737667d-bda1-47e1-bb00-01473a00d1dd"],
        // Klasyczny burger wołowy z cheddarem · Klopsiki szwedzkie z ziemniakami i żurawiną
        "protein:dinner:beef": ["2944b688-7ad9-4bd7-86e8-6cfe7e4b46b2", "f2f7529b-4d6f-4db5-929f-916f5978a80e"],
        // Łosoś z grilla z cytryną i ziołami · Sałatka z pieczonym łososiem, ogórkiem i koperkiem
        "protein:dinner:fish": ["39b2f714-b035-4f82-a572-6b8091653f41", "46d1fefa-ef45-44f7-a866-4cb4871f9ee2"],
        // Szaszłyki z halloumi i warzyw · Pizza na tortilli z warzywami
        "protein:dinner:veg": ["735c7905-e3f0-413d-8069-97c3c31d2040", "106e26e0-6512-46cd-9ed6-d0efcb565fcf"],
        // — Pora w planie (przekąski) —
        // Wrap z kurczakiem tikka i sosem jogurtowym · Jogurt kokosowy z mango i granolą
        "slot:snacks:secondBreakfast": ["50a47f30-f810-4994-b061-2aefedb38dfb", "13147df6-5d57-4e64-9ab5-528f7ecc40d3"],
        // Ciasto z rabarbarem i kruszonką · Ciasto ucierane ze śliwkami
        "slot:snacks:afternoonSnack": ["bb1b5226-75be-4e56-a97f-cbc293b380c4", "2daeae9c-528a-4af5-8a81-df08f8266565"],
        // Młoda marchewka z hummusem · Chipsy z buraka z tymiankiem
        "slot:snacks:snack": ["c975e5a9-e881-4d4b-96b0-a739379c4494", "1a7f321c-d654-4db2-a768-36cd52084776"],
    ]
}
