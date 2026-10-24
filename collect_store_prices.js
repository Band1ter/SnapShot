// Snapshot price collector
// ------------------------
// Refreshes SnapShot/store_prices.json with current prices from the stores' online stores (via Instacart).

(async () => {
  const HASH = {
    search: "4436919b666ee155fed657904322223b01f4f3d22b67eeeb9bfdde71dbf5b560",
    items: "9e71beac4c2151e246377e4c892f3898c239abf65ff0423c04cf7bcdf964c8aa",
  };
  const POSTAL = "08902", ZONE = "736";
  const STORES = [
    ["ALDI", "37501"], ["ShopRite of New Brunswick", "93031"], ["Stop & Shop", "444410"],
    ["BJ's Wholesale Club", "525000"], ["CVS Pharmacy", "45748"], ["Walgreens", "11591"],
  ];
  const TERMS = `whole milk;2% milk;skim milk;lactose free milk;almond milk;oat milk;soy milk;chocolate milk;eggs;large eggs dozen;butter;margarine;cheddar cheese;mozzarella cheese;american cheese slices;shredded cheese;cream cheese;cottage cheese;sour cream;greek yogurt;yogurt;heavy cream;half and half;coffee creamer;white bread;whole wheat bread;hamburger buns;hot dog buns;bagels;english muffins;flour tortillas;corn tortillas;pita bread;dinner rolls;white rice;brown rice;jasmine rice;spaghetti;penne pasta;macaroni;egg noodles;ramen noodles;macaroni and cheese;oatmeal;instant oatmeal;cheerios;corn flakes;frosted flakes;raisin bran;granola;pancake mix;all purpose flour;sugar;brown sugar;cornmeal;bread crumbs;black beans;pinto beans;kidney beans;chickpeas;refried beans;baked beans;lentils;dry pinto beans;canned corn;canned green beans;canned peas;canned tomatoes;tomato sauce;tomato paste;pasta sauce;chicken noodle soup;tomato soup;cream of mushroom soup;chicken broth;canned tuna;canned chicken;canned salmon;spam;vienna sausages;canned peaches;canned pineapple;fruit cocktail;applesauce;peanut butter;grape jelly;strawberry jam;honey;maple syrup;vegetable oil;olive oil;canola oil;vinegar;ketchup;mustard;mayonnaise;salsa;hot sauce;soy sauce;salt;black pepper;garlic powder;cinnamon;chicken bouillon;baking soda;baking powder;vanilla extract;chicken breast;chicken thighs;whole chicken;chicken drumsticks;chicken wings;ground beef;ground turkey;beef stew meat;pork chops;pork shoulder;bacon;breakfast sausage;hot dogs;deli turkey;deli ham;bologna;salami;tilapia;salmon fillet;frozen shrimp;fish sticks;tofu;bananas;apples;gala apples;oranges;clementines;grapes;strawberries;blueberries;lemons;limes;pears;peaches;watermelon;cantaloupe;pineapple;mango;avocado;tomatoes;potatoes;sweet potatoes;onions;yellow onion;garlic;carrots;baby carrots;celery;broccoli;cauliflower;lettuce;romaine lettuce;spinach;salad mix;cucumber;green peppers;bell peppers;jalapeno;zucchini;corn on the cob;mushrooms;green beans;cabbage;cilantro;frozen broccoli;frozen mixed vegetables;frozen peas;frozen corn;frozen spinach;frozen strawberries;frozen blueberries;frozen pizza;frozen waffles;frozen burritos;frozen chicken nuggets;frozen french fries;ice cream;frozen dinner;orange juice;apple juice;grape juice;cranberry juice;bottled water;sparkling water;coffee;ground coffee;tea bags;cola;lemonade;sports drink;potato chips;tortilla chips;pretzels;popcorn;saltine crackers;graham crackers;goldfish crackers;cookies;oreo;granola bars;fruit snacks;raisins;peanuts;almonds;trail mix;chocolate bar;baby formula;baby food;infant cereal;seeds vegetable;tomato plant;multivitamin;vitamin d;protein powder;energy drink;paper towels;toilet paper;laundry detergent;dish soap;dog food;cat food;diapers;rotisserie chicken`
    .split(";").map(s => s.trim()).filter(Boolean);

  const gql = async (op, vars, hash) => {
    const u = "/graphql?operationName=" + op + "&variables=" + encodeURIComponent(JSON.stringify(vars)) +
      "&extensions=" + encodeURIComponent(JSON.stringify({ persistedQuery: { version: 1, sha256Hash: hash } }));
    const r = await fetch(u, { headers: { accept: "application/json" } });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.json();
  };
  const search = async (shopId, q, n = 6) => {
    const base = { shopId, postalCode: POSTAL, zoneId: ZONE };
    const j = await gql("SearchResultsPlacements", {
      action: null, query: q, pageViewId: crypto.randomUUID(), elevatedProductId: null, searchSource: "search",
      filters: [], disableReformulation: false, disableLlm: false, forceInspiration: false, orderBy: "bestMatch",
      clusterId: null, includeDebugInfo: false, clusteringStrategy: null,
      contentManagementSearchParams: { itemGridColumnCount: 4 }, ...base, first: 10,
    }, HASH.search);
    const ids = [...new Set(JSON.stringify(j).match(/items_\d+-\d+/g) || [])].slice(0, n);
    if (!ids.length) return [];
    const it = await gql("Items", { ids, ...base }, HASH.items);
    return (it.data.items || []).map(i => {
      const c = i.price?.viewSection?.itemCard || {};
      return { n: i.name, s: i.size || "", p: c.priceString, f: c.plainFullPriceString, u: c.pricingUnitString,
               a: i.availability?.available ?? null };
    });
  };

  // Collect with 3 parallel workers that share the work.
  const data = {};
  let done = 0, total = TERMS.length * STORES.length;
  const worker = async order => {
    for (const [store, id] of order) {
      data[store] = data[store] || {};
      for (const t of TERMS) {
        if (data[store][t] !== undefined) continue;
        data[store][t] = null;
        for (let tries = 1; ; tries++) {
          try { data[store][t] = await search(id, t); break; }
          catch (e) { if (tries >= 3) { console.warn(store, t, e.message); data[store][t] = []; break; } }
        }
        done++;
        if (done % 50 === 0) console.log(`Snapshot prices: ${done}/${total}`);
      }
    }
  };
  const S = STORES;
  await Promise.all([worker(S), worker([S[2], S[3], S[4], S[5], S[0], S[1]]), worker([...S].reverse())]);

  // Convert to the app's format, keeping only items whose name contains the staple's key words.
  const tok = s => new Set(s.toLowerCase().replace(/[^a-z0-9]+/g, " ").split(" ")
    .filter(w => w.length > 1 && !/^\d/.test(w))
    .map(w => w.length > 4 && /(oes|ches|shes)$/.test(w) ? w.slice(0, -2)
      : w.length > 3 && w.endsWith("ies") ? w.slice(0, -3) + "y"
      : w.length > 3 && w.endsWith("s") && !w.endsWith("ss") ? w.slice(0, -1) : w));
  const ignore = new Set(["dozen", "large", "canned", "dry", "frozen", "fresh", "instant", "all", "purpose", "bag", "seed", "plant"]);
  const nonFood = /pantyhose|hosiery|\btoy\b|lotion|shampoo/i;
  const num = s => { const m = (s || "").replace(/,/g, "").match(/\$?\s*(\d+(?:\.\d+)?)/); return m ? parseFloat(m[1]) : null; };
  const stores = {};
  for (const [store, terms] of Object.entries(data)) {
    const seen = new Map();
    for (const [term, items] of Object.entries(terms)) {
      const need = [...tok(term)].filter(w => !ignore.has(w));
      (items || []).forEach((it, rank) => {
        if (it.a === false || nonFood.test(it.n) || !need.every(w => tok(it.n).has(w))) return;
        let p, u = null;
        const per = (it.u || "").match(/\$\s*(\d+(?:\.\d+)?)\s*\/\s*([a-z]+)/i);
        if (per) { p = parseFloat(per[1]); u = per[2].toLowerCase(); } else { p = num(it.p); }
        if (p == null) return;
        const r = num(it.f);
        const key = it.n + "|" + it.s;
        if (!seen.has(key)) seen.set(key, { t: term, n: it.n, s: it.s, p, r: r && r > p ? r : null, u, rank });
      });
    }
    stores[store] = [...seen.values()];
  }
  const out = { collectedAt: new Date().toISOString(), postalCode: POSTAL,
                source: "Store online storefronts via Instacart", stores };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(out)], { type: "application/json" }));
  a.download = "store_prices.json";
  document.body.appendChild(a); a.click(); a.remove();
  console.log("Snapshot prices: done", Object.fromEntries(Object.entries(stores).map(([k, v]) => [k, v.length])));
})();
