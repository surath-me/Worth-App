/* Development only: builds about a year of realistic sample data for Worth, ending in the current month.
   Loaded on demand from Settings → Developer → Load sample data (shown only on the dev domain and localhost).
   It is deterministic (seeded), so every load gives the same curves. */

const MONTHS = 13; // this month plus the 12 before it, so the 1Y chart is full

// small seeded PRNG so the sample looks the same every time
function rng(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const key = d => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0");

// market mood per month (0 = oldest): a steady climb with a dip around months 5–7 and a recovery after
const MARKET = [0.012, 0.021, 0.008, 0.017, -0.012, -0.095, -0.07, 0.028, 0.045, 0.02, 0.026, -0.022, 0.019];

/* Each entry: how it starts, how it moves each month, and (optionally) when it opens or closes.
   step(prev, i, r) returns the next balance; r() is a random number 0..1. */
const ENTRIES = [
  { id: "s-n26", name: "Everyday", platform: "N26", type: "bank", cur: "EUR", start: 3200,
    step: (p, i, r) => 2600 + r() * 2400 },                                      // salary in, spending out
  { id: "s-dkb", name: "Savings", platform: "DKB", type: "bank", cur: "EUR", start: 8000,
    step: (p, i, r) => p + 450 + r() * 300 },                                    // steady saving
  { id: "s-tr-etf", name: "World ETF", platform: "Trade Republic", type: "etf", cur: "EUR", start: 18500,
    step: (p, i, r) => p * (1 + MARKET[i] + (r() - 0.5) * 0.01) + 500 },         // €500 savings plan
  { id: "s-scal", name: "Tech stocks", platform: "Scalable Capital", type: "stocks", cur: "EUR", start: 6200,
    step: (p, i, r) => p * (1 + MARKET[i] * 1.8 + (r() - 0.5) * 0.05) },         // more volatile
  { id: "s-zerodha", name: "Indian stocks", platform: "Zerodha", type: "stocks", cur: "INR", start: 620000,
    step: (p, i, r) => p * (1 + MARKET[i] * 0.8 + 0.006 + (r() - 0.5) * 0.04) },
  { id: "s-kuvera", name: "Index funds SIP", platform: "Kuvera", type: "mf", cur: "INR", start: 310000,
    step: (p, i, r) => p * (1 + MARKET[i] * 0.7 + 0.005 + (r() - 0.5) * 0.015) + 15000 }, // ₹15k SIP
  { id: "s-hdfc", name: "Salary account (India)", platform: "HDFC Bank", type: "bank", cur: "INR", start: 210000,
    step: (p, i, r) => p + (r() - 0.45) * 30000 },
  { id: "s-coinbase", name: "Bitcoin", platform: "Coinbase", type: "crypto", cur: "USD", start: 2100,
    step: (p, i, r) => p * (1 + MARKET[i] * 3 + (r() - 0.45) * 0.18) },          // swings hard
  { id: "s-revolut", name: "Travel card", platform: "Revolut", type: "bank", cur: "GBP", start: 900,
    step: (p, i, r) => p - 60 + r() * 80, closesAt: 7 },                          // closed mid-year, stays in history
  { id: "s-gold", name: "Gold coins", platform: "", type: "other", cur: "EUR", start: 2500, opensAt: 4,
    step: (p, i, r) => p * (1 + 0.008 + (r() - 0.5) * 0.03) },                   // bought a few months in
  { id: "s-cash", name: "Wallet", platform: "", type: "cash", cur: "EUR", start: 250,
    step: (p, i, r) => 150 + r() * 250 },
  // physical assets and debts
  { id: "s-flat", name: "Flat in Stuttgart", platform: "", type: "property", cur: "EUR", start: 345000, dep: 2,
    step: (p, i, r) => p * Math.pow(1.02, 1 / 12) },                             // +2% a year
  { id: "s-car", name: "VW Golf", platform: "", type: "vehicle", cur: "EUR", start: 23500, dep: -15,
    step: (p, i, r) => p * Math.pow(0.85, 1 / 12) },                             // −15% a year
  { id: "s-mortgage", name: "Home loan", platform: "Sparkasse", type: "mortgage", cur: "EUR", start: 268000,
    step: (p, i, r) => p - 820 },                                                // principal paid each month
  { id: "s-card", name: "Credit card", platform: "Revolut", type: "card", cur: "EUR", start: 640,
    step: (p, i, r) => 250 + r() * 1300 }
];

export function makeSample(now = new Date()) {
  const r = rng(42);
  const months = [];
  for (let k = MONTHS - 1; k >= 0; k--) months.push(key(new Date(now.getFullYear(), now.getMonth() - k, 1)));

  const bal = {};
  ENTRIES.forEach(e => (bal[e.id] = e.start));
  const snaps = {};

  months.forEach((m, i) => {
    // rates drift a little month to month (units per 1 EUR)
    const rates = {
      EUR: 1,
      INR: +(104 + i * 0.5 + (r() - 0.5) * 1.6).toFixed(2),
      USD: +(1.09 + i * 0.006 + (r() - 0.5) * 0.02).toFixed(4),
      GBP: +(0.85 + (r() - 0.5) * 0.02).toFixed(4),
      CHF: +(0.94 + (r() - 0.5) * 0.015).toFixed(4)
    };
    const items = {};
    ENTRIES.forEach(e => {
      if (i > 0) bal[e.id] = Math.max(0, e.step(bal[e.id], i, r));
      const open = (e.opensAt == null || i >= e.opensAt) && (e.closesAt == null || i < e.closesAt);
      if (open) items[e.id] = [Math.round(bal[e.id] * 100) / 100, e.cur, e.type, e.name];
    });
    snaps[m] = { items, rates };
  });

  // The current month isn't checked in yet: balances still hold last month's values (like real use),
  // so Monthly shows "Update <month>" and the update sheet carries values over, with the car depreciated.
  const cur = months[months.length - 1], prevKey = months[months.length - 2];
  const last = snaps[cur], prev = snaps[prevKey];
  const accounts = ENTRIES.filter(e => prev.items[e.id]).map(e => {
    const a = { id: e.id, name: e.name, type: e.type, platform: e.platform, cur: e.cur, bal: prev.items[e.id][0] };
    if (e.dep != null) a.dep = e.dep;
    return a;
  });
  snaps[cur] = { items: { ...prev.items }, rates: { ...last.rates } };

  return {
    v: 1, base: "EUR", rates: { ...last.rates }, ratesAt: null,
    accounts, snaps, lastCheckin: prevKey, updatedAt: now.getTime()
  };
}
