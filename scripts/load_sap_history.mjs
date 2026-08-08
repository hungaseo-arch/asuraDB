#!/usr/bin/env node
/**
 * SAP 거래이력(판매 A/R · 구매 A/P) 정규화 적재.
 *
 *   node scripts/load_sap_history.mjs --dry     # 파싱·검증만
 *   node scripts/load_sap_history.mjs           # Supabase 업서트
 *   node scripts/load_sap_history.mjs --only=sales|purchases
 *
 * 원본은 Google Drive 03-Claude/sap 의 xlsx 3종 중 AR·AP 2종.
 * (배송 delivery_2020-2026.xlsx 는 적재 완료되어 여기서 다루지 않는다.)
 *
 * 정규화 규칙
 *  - 헤더(거래처·일자·PO·환율·status)를 라인에서 분리.
 *  - 라인은 doc+sku+단가 가 같으면 하나로 통합(qty·할인액 합산) → 수량/금액 합계는 보존.
 *  - 파생값(금액 = qty×단가, USD = IDR÷환율)은 저장하지 않고 뷰에서 계산.
 */
import fs from 'node:fs'
import path from 'node:path'
import XLSX from 'xlsx'
import { createClient } from '@supabase/supabase-js'

const SAP_DIR = '/Users/seojonghwan/Library/CloudStorage/GoogleDrive-hunga.seo@gmail.com/내 드라이브/03-Claude/sap'
const FILES = {
  sales: { file: '6.3 AR Invoice Status_2020-2026.xlsx', expect: { headers: 28470, lines: 65470 } },
  purchases: { file: '9.1 AP Invoice Status_2020-2026.xlsx', expect: { headers: 6237, lines: 21539 } },
}
const STATUS = {
  'A/R INVOICE': 'INV',
  'A/R INVOICE CANCELLED': 'INV_CXL',
  'A/R CREDIT MEMO': 'CM',
  'A/R CREDIT MEMO CANCELLED': 'CM_CXL',
  'A/P INVOICE': 'INV',
  'A/P INVOICE CANCELLED': 'INV_CXL',
}
// 원본 열 위치 (헤더행 index 4 기준, AR·AP 동일 레이아웃)
const C = { type0: 0, type1: 1, type2: 2, type3: 3, doc: 4, po: 5, date: 6, buyer: 7, brand: 8, sku: 9, desc: 10, qty: 11, price: 12, disc: 14, rate: 18, deliv: 19, type: 20 }

const argv = process.argv.slice(2)
const DRY = argv.includes('--dry')
const only = (argv.find(a => a.startsWith('--only=')) || '').split('=')[1]

const s = v => (v === null || v === undefined ? '' : String(v).trim())
const num = v => {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(String(v).replace(/,/g, ''))
  return Number.isFinite(n) ? n : null
}
const serialToDate = v => {
  const n = num(v)
  if (n === null || n <= 0) return null
  const ms = Date.UTC(1899, 11, 30) + Math.round(n) * 86400000
  return new Date(ms).toISOString().slice(0, 10)
}
const nameKey = v => s(v).toUpperCase().replace(/[.,]/g, ' ').replace(/\s+/g, ' ').trim()

function parse(kind) {
  const { file } = FILES[kind]
  const wb = XLSX.readFile(path.join(SAP_DIR, file), { raw: true })
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: true, defval: null, blankrows: false })

  const headers = new Map()      // doc_no -> header
  const lineMap = new Map()      // doc_no -> Map(sku|price -> line)
  const items = new Map()        // sku -> {description, brand, type0..3}
  const partners = new Set()
  const issues = { totalRows: 0, skipped: 0, headerConflict: [], badStatus: new Set(), noSku: 0 }

  for (let i = 5; i < rows.length; i++) {
    const r = rows[i]
    if (!r) continue
    const doc = num(r[C.doc])
    // 합계(Total) 행·빈 행 제거
    if (doc === null || s(r[C.type1]).toUpperCase() === 'TOTAL') { issues.skipped++; continue }
    issues.totalRows++

    const st = STATUS[s(r[C.type]).toUpperCase()]
    if (!st) { issues.badStatus.add(s(r[C.type])); continue }

    const buyer = s(r[C.buyer])
    partners.add(buyer)
    const h = {
      doc_no: doc,
      inv_date: serialToDate(r[C.date]),
      partner: buyer,
      po: s(r[C.po]) || null,
      ex_rate: num(r[C.rate]),
      status: st,
      delivery_date: serialToDate(r[C.deliv]),
    }
    const prev = headers.get(doc)
    if (!prev) headers.set(doc, h)
    else {
      for (const k of ['inv_date', 'partner', 'po', 'ex_rate', 'status', 'delivery_date']) {
        if (prev[k] !== h[k]) {
          if (prev[k] === null && h[k] !== null) prev[k] = h[k]           // 결측 보완
          else if (h[k] !== null) issues.headerConflict.push({ doc, k, a: prev[k], b: h[k] })
        }
      }
    }

    const sku = s(r[C.sku]) || null
    if (!sku) issues.noSku++
    if (sku && !items.has(sku)) items.set(sku, null)
    if (sku) {
      items.set(sku, { sku, description: s(r[C.desc]), brand: s(r[C.brand]) || null, type0: s(r[C.type0]) || null, type1: s(r[C.type1]) || null, type2: s(r[C.type2]) || null, type3: s(r[C.type3]) || null })
    }

    const qty = num(r[C.qty]) ?? 0
    const price = num(r[C.price]) ?? 0
    const disc = num(r[C.disc])
    if (!lineMap.has(doc)) lineMap.set(doc, new Map())
    const key = `${sku ?? ''}|${price}`
    const bucket = lineMap.get(doc)
    const ex = bucket.get(key)
    if (ex) { ex.qty += qty; ex.disc_amount_idr = (ex.disc_amount_idr ?? 0) + (disc ?? 0) }
    else bucket.set(key, { doc_no: doc, line_no: bucket.size + 1, sku, qty, unit_price_idr: price, disc_amount_idr: disc })
  }

  const lines = []
  for (const [, bucket] of lineMap) for (const l of bucket.values()) lines.push(l)
  return { headers: [...headers.values()], lines, items: [...items.values()].filter(Boolean), partners: [...partners], issues, rawRows: issues.totalRows }
}

// ---- 검증 리포트 -----------------------------------------------------------
function report(kind, p) {
  const { expect } = FILES[kind]
  const sumQty = p.lines.reduce((a, l) => a + l.qty, 0)
  const sumDisc = p.lines.reduce((a, l) => a + (l.disc_amount_idr ?? 0), 0)
  console.log(`\n[${kind}] 원본 데이터행 ${p.rawRows} (제외 ${p.issues.skipped})`)
  console.log(`  헤더 ${p.headers.length} (목표 ${expect.headers}) ${p.headers.length === expect.headers ? '✓' : '✗'}`)
  console.log(`  라인 ${p.lines.length} (목표 ${expect.lines}) ${p.lines.length === expect.lines ? '✓' : '✗'}`)
  console.log(`  수량합 ${sumQty.toLocaleString()} · 할인후금액합 ${Math.round(sumDisc).toLocaleString()} IDR`)
  console.log(`  품목 ${p.items.length} · 거래처 ${p.partners.length} · sku 없는 행(운임 등) ${p.issues.noSku}`)
  if (p.issues.badStatus.size) console.log('  ⚠ 미매핑 status:', [...p.issues.badStatus])
  if (p.issues.headerConflict.length) {
    console.log(`  ⚠ 헤더 불일치 ${p.issues.headerConflict.length}건 (첫 5)`, p.issues.headerConflict.slice(0, 5))
  }
  return { sumQty, sumDisc }
}

// ---- 적재 ------------------------------------------------------------------
function env() {
  const raw = fs.readFileSync(path.resolve(process.cwd(), '.env'), 'utf8')
  const get = k => (raw.match(new RegExp(`^${k}\\s*=\\s*(.+)$`, 'm')) || [])[1]?.trim().replace(/^["']|["']$/g, '')
  return { url: get('SUPABASE_URL'), key: get('SUPABASE_SERVICE_KEY') }
}

async function upsert(sb, table, rows, conflict, chunk = 1000) {
  for (let i = 0; i < rows.length; i += chunk) {
    const slice = rows.slice(i, i + chunk)
    const { error } = await sb.from(table).upsert(slice, { onConflict: conflict, defaultToNull: false })
    if (error) throw new Error(`${table} @${i}: ${error.message}`)
    process.stdout.write(`\r  ${table}: ${Math.min(i + chunk, rows.length)}/${rows.length}`)
  }
  process.stdout.write('\n')
}

async function main() {
  const kinds = only ? [only] : ['sales', 'purchases']
  const parsed = {}
  for (const k of kinds) { parsed[k] = parse(k); report(k, parsed[k]) }

  if (DRY) { console.log('\n--dry: 적재하지 않고 종료'); return }

  const { url, key } = env()
  if (!url || !key) throw new Error('.env 에 SUPABASE_URL / SUPABASE_SERVICE_KEY 필요')
  const sb = createClient(url, key, { auth: { persistSession: false } })

  // 거래처 id 매핑 (기존 sap_partners 재사용, 없으면 신규 id 부여)
  const { data: pRows, error: pErr } = await sb.from('sap_partners').select('id,name,is_customer,is_supplier')
  if (pErr) throw pErr
  const byKey = new Map(pRows.map(r => [nameKey(r.name), r]))
  let nextId = Math.max(0, ...pRows.map(r => r.id)) + 1
  const newPartners = []
  for (const k of kinds) {
    const flag = k === 'sales' ? 'is_customer' : 'is_supplier'
    for (const name of parsed[k].partners) {
      let p = byKey.get(nameKey(name))
      if (!p) {
        p = { id: nextId++, name, is_customer: false, is_supplier: false, customer_id: null }
        byKey.set(nameKey(name), p); newPartners.push(p)
      }
      if (!p[flag]) { p[flag] = true; if (!newPartners.includes(p)) newPartners.push(p) }
    }
  }
  if (newPartners.length) {
    console.log(`거래처 신규/플래그 갱신 ${newPartners.length}건`)
    await upsert(sb, 'sap_partners', newPartners.map(({ id, name, is_customer, is_supplier }) => ({ id, name, is_customer, is_supplier })), 'id')
  }

  // 품목 (기존 932 유지 + 미등록만 추가)
  const { data: iRows, error: iErr } = await sb.from('sap_items').select('sku')
  if (iErr) throw iErr
  const known = new Set(iRows.map(r => r.sku))
  const newItems = []
  for (const k of kinds) for (const it of parsed[k].items) if (!known.has(it.sku)) { known.add(it.sku); newItems.push(it) }
  if (newItems.length) { console.log(`품목 신규 ${newItems.length}건`); await upsert(sb, 'sap_items', newItems, 'sku') }

  const T = {
    sales: ['sap_sales_invoices', 'sap_sales_invoice_lines'],
    purchases: ['sap_purchase_invoices', 'sap_purchase_invoice_lines'],
  }
  for (const k of kinds) {
    const [ht, lt] = T[k]
    const heads = parsed[k].headers.map(h => ({
      doc_no: h.doc_no, inv_date: h.inv_date, partner_id: byKey.get(nameKey(h.partner)).id,
      po: h.po, ex_rate: h.ex_rate, status: h.status, delivery_date: h.delivery_date,
    }))
    console.log(`\n${ht} 업서트 ${heads.length}`)
    await upsert(sb, ht, heads, 'doc_no')
    console.log(`${lt} 업서트 ${parsed[k].lines.length}`)
    await upsert(sb, lt, parsed[k].lines, 'doc_no,line_no', 2000)
  }
  console.log('\n완료')
}

main().catch(e => { console.error('\n실패:', e.message); process.exit(1) })
