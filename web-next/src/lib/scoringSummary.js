// "Tổng kết tiền" of one customer over the days on screen (Tính điểm):
//   (1) what the customer sent: how many lô (numbers), how many điểm, converted to đồng;
//   (2) what won: how many lô hit, which ones and the money;
//   (3) the rest = (1) - (2).
// (2) and (3) only cover the days that already have a lottery result; the stakes of days
// without a result are reported separately as "chưa có kết quả" and not counted in (3).
import { effectiveConfig, effectiveSource, hasMoneyModel, isTableKind, pointValueOf, toMoney, unitOf } from './scoringConfig.js'
import { entryStations, regionOf } from './lotteryStations.js'

const fold = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd').toLowerCase()

const toNumber = (v) => {
  const n = parseFloat(String(v ?? '').replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
export const normDigits = (str, count) => {
  const d = String(str || '').replace(/\D/g, '')
  return d ? d.slice(-count).padStart(count, '0') : ''
}
const BASE_TIERS = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay']
const TIER_FIELDS = [...BASE_TIERS, 'giaiTam']
// The numbers of the prize groups a bet type checks. A config that ticks all eight classic groups means "every prize",
// so on a Miền Nam / Miền Trung result it includes the eighth prize (giaiTam) too.
export function numbersForTiers(r, tiers) {
  const out = []
  const all = BASE_TIERS.every((t) => tiers.includes(t))
  for (const t of tiers) if (TIER_FIELDS.includes(t)) out.push(...[].concat(r[t] ?? []))
  if (all && !tiers.includes('giaiTam')) out.push(...[].concat(r.giaiTam ?? []))
  return out
}

// The hit count of "bảng cấu hình" rows. `ctx` = { region: 'mb'|'mt'|'mn' (of the station), customerRegion: 'mb'|'mn'|null }.
// Every kind reads the numbers of its "lấy số" (scoringConfig `effectiveSource`: giải nào, vị trí đầu / cuối, bao nhiêu số, lô
// thứ mấy); what each kind does with them:
//   lo / lo3 / lo4 / dau / duoi / cang3 / cang4 / custom   each number the customer wrote is compared with those numbers;
//                  every match is a hit (it comes up in several lô = several hits)
//   dau on a Miền Bắc result with the built-in "lấy số": a Bắc customer = the first prize; a Nam/Trung customer = the four
//          seventh prizes with the stake ×4 ("1 điểm đầu = 4.000đ")
//   xienN  true xiên: every one of the N numbers must be among them; it wins ONCE per entry
//   truotN lô trượt: none of the N numbers may be among them; it wins once, stake = điểm × N × giá
//   tai_xiu / chan_le  the first number read: 00-49 xỉu, 50-99 tài (last 2 digits); even / odd last digit
export function sourceNumbers(lr, src) {
  if (!lr) return []
  const out = []
  for (const t of src.tiers) {
    let list = [].concat(lr[t] ?? []).map(String)
    if (src.pick?.length) list = src.pick.map((i) => list[i - 1]).filter((x) => x != null)
    out.push(...list)
  }
  return out
}
const piece = (n, src, d = src.digits) => (src.position === 'first' ? n.slice(0, d) : n.slice(-d))

function tableDetail(entry, lr, config, ctx) {
  const kind = config.kind
  const score = toNumber(entry.score)
  const toks = String(entry.value || '').split(/[,;\s]+/).filter(Boolean)
  const region = ctx.region || 'mb'
  const south = ctx.customerRegion === 'mn'
  let src = effectiveSource(config, kind, region)
  let stakeFactor = 1
  if (kind === 'dau' && region === 'mb' && south && !config.source) {
    src = { tiers: ['giaiBay'], position: 'last', digits: 2 }
    stakeFactor = 4
  }
  const nums = sourceNumbers(lr, src)
  const d = src.digits

  if (kind.startsWith('xien') || kind.startsWith('truot')) {
    // xiên: every number must be among the day's numbers; trượt: none of them may be. Either way it is one bet that pays once.
    const trượt = kind.startsWith('truot')
    const n = Number(kind.slice(trượt ? 5 : 4))
    const bets = toks.map((t) => normDigits(t, d)).filter(Boolean)
    const day = new Set(nums.filter((x) => x.length >= d).map((x) => piece(x, src)))
    const ok = lr && bets.length === n && new Set(bets).size === n
    const hit = ok && (trượt ? bets.every((x) => !day.has(x)) : bets.every((x) => day.has(x))) ? 1 : 0
    return { bets, lots: Math.max(1, bets.length), stakeFactor: 1, perNumber: [{ number: bets.join('.'), hits: hit }], totalHits: hit, score }
  }
  if (kind === 'tai_xiu' || kind === 'chan_le') {
    // Thần tài: not a number but a property of the number read (2 last digits: 00-49 xỉu / 50-99 tài; last digit: chẵn / lẻ).
    const first = nums[0] || ''
    const tail = first.slice(-2)
    const props = kind === 'tai_xiu' ? { tai: tail !== '' && tail >= '50', xiu: tail !== '' && tail < '50' } : { chan: first !== '' && Number(first.slice(-1)) % 2 === 0, le: first !== '' && Number(first.slice(-1)) % 2 === 1 }
    const word = (t) => fold(t).replace(/[^a-z]/g, '')
    const alias = { t: 'tai', tai: 'tai', x: 'xiu', xiu: 'xiu', c: 'chan', chan: 'chan', l: 'le', le: 'le' }
    const bets = toks.map((t) => alias[word(t)]).filter((w) => w && w in props)
    const perNumber = bets.map((number) => ({ number, hits: lr && props[number] ? 1 : 0 }))
    return { bets, lots: Math.max(1, bets.length), stakeFactor: 1, perNumber, totalHits: perNumber.reduce((a, b) => a + b.hits, 0), score }
  }
  const bets = toks.map((t) => normDigits(t, d)).filter(Boolean)
  const long = nums.filter((x) => x.length >= d).map((x) => piece(x, src))
  const perNumber = bets.map((number) => ({ number, hits: long.filter((x) => x === number).length }))
  return { bets, lots: Math.max(1, bets.length), stakeFactor, perNumber, totalHits: perNumber.reduce((a, b) => a + b.hits, 0), score }
}

// One entry against one day's result: its numbers, hits per number and the points/money out.
export function entryDetail(entry, lr, config, ctx = {}) {
  if (isTableKind(config.kind) || (config.kind === 'custom' && config.source)) {
    const d = tableDetail(entry, lr, config, ctx)
    return { ...d, out: d.totalHits > 0 ? d.score * config.rate * d.totalHits : 0 }
  }
  const digits = config.digits || 2
  const bets = String(entry.value || '').split(/[,;\s]+/).map((v) => normDigits(v, digits)).filter(Boolean)
  const trailing = lr ? numbersForTiers(lr, config.tiers).map((n) => String(n).slice(-digits)) : []
  const score = toNumber(entry.score)
  const perNumber = bets.map((number) => ({ number, hits: trailing.filter((x) => x === number).length }))
  const totalHits = perNumber.reduce((a, b) => a + b.hits, 0)
  return { bets, lots: Math.max(1, bets.length), stakeFactor: 1, perNumber, score, out: totalHits > 0 ? score * config.rate * totalHits : 0 }
}

// Money of a stake / a win, in đồng. A row with the money model (price + payout) is exact; an older row goes through
// unit / pointValue / rate as before.
export const stakeMoney = (key, cfg, stake) => (hasMoneyModel(cfg) ? stake * cfg.price : toMoney(key, cfg, stake))
export const winMoney = (key, cfg, score, hits) => (hasMoneyModel(cfg) ? score * hits * cfg.payout : toMoney(key, cfg, score * cfg.rate * hits))

// days: [{ date, entries }]; getResult(date, station) -> result | null | undefined (not known yet = pending).
// An entry on a region ('mn' / 'mt') counts once for EVERY station of that region drawing that day (stake and
// prizes are per station).
export function summarize(days, accountRates, customerRates, getResult, opts = {}) {
  const byType = new Map()
  const won = []
  const sent = { lots: 0, points: 0, money: 0 }
  const settled = { lots: 0, money: 0 } // sent on days that have a result
  const pending = { lots: 0, money: 0 } // sent on days without a result yet
  let wonMoney = 0
  let wonHits = 0

  for (const day of days) {
    for (const entry of day.entries) {
      const key = entry.betType || 'de'
      const stations = entryStations({ ...entry, entryDate: entry.entryDate || day.date })
      for (const station of stations.length ? stations : ['mb']) {
        // Rates can differ by region (Miền Bắc has 27 numbers a day, Miền Nam / Miền Trung 18).
        const cfg = effectiveConfig(accountRates, customerRates, key, regionOf(station).id)
        const unit = unitOf(key, cfg)
        const lr = getResult(day.date, station)
        const region = regionOf(station).id
        const d = entryDetail(entry, lr, cfg, { region, customerRegion: opts.customerRegion })
        const stake = d.score * d.lots * (d.stakeFactor || 1) // each number carries the entry's score
        const stakeMoneyValue = stakeMoney(key, cfg, stake)

        let t = byType.get(key)
        if (!t) byType.set(key, (t = { key, unit, pointValue: hasMoneyModel(cfg) ? cfg.price : pointValueOf(cfg), lots: 0, amount: 0, money: 0 }))
        t.lots += d.lots
        t.amount += stake
        t.money += stakeMoneyValue
        sent.lots += d.lots
        sent.money += stakeMoneyValue
        if (unit === 'point') sent.points += stake

        if (!lr) {
          pending.lots += d.lots
          pending.money += stakeMoneyValue
          continue
        }
        settled.lots += d.lots
        settled.money += stakeMoneyValue
        for (const n of d.perNumber) {
          if (!n.hits) continue
          const money = winMoney(key, cfg, d.score, n.hits)
          won.push({ date: day.date, type: key, station, number: n.number, hits: n.hits, money })
          wonMoney += money
          wonHits += n.hits
        }
      }
    }
  }
  won.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.money - a.money))
  return {
    sent,
    byType: [...byType.values()],
    settled,
    pending,
    won: { lots: won.length, hits: wonHits, items: won, money: wonMoney },
    remaining: settled.money - wonMoney,
  }
}
