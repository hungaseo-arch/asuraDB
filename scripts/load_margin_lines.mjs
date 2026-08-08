#!/usr/bin/env node
/**
 * 마진 명세 적재 — sales analysis report <YYYY-MM>.xlsx 의 「1.Row_Data」 시트 → margin_lines
 *
 *   node scripts/load_margin_lines.mjs --dry            # 파싱·검증만
 *   node scripts/load_margin_lines.mjs                  # 전 월 적재
 *   node scripts/load_margin_lines.mjs --month=2026-07  # 특정 월만
 *
 * 원본은 Google Drive 01-ASCENDO/01.보고서/01-2.월간업무보고/<YYYY>년 월간업무보고/.
 * 월 단위로 delete 후 insert 하므로 재실행해도 안전(멱등).
 *
 * 검증: 각 월의 명세 합계(수량·매출·마진)를 같은 파일의 요약 시트 TOTAL 과 대조한다.
 * 컬럼은 위치가 아니라 **헤더 이름**으로 찾는다(2024-07 파일만 'Type 4' 열이 하나 더 있어 위치가 밀림).
 */
import fs from 'node:fs'
import path from 'node:path'
import XLSX from 'xlsx'
import { createClient } from '@supabase/supabase-js'

const ROOT = '/Users/seojonghwan/Library/CloudStorage/GoogleDrive-hunga.seo@gmail.com/내 드라이브/01-ASCENDO/01.보고서/01-2.월간업무보고'
const YEARS = ['2021', '2022', '2023', '2024', '2025', '2026']

const argv = process.argv.slice(2)
const DRY = argv.includes('--dry')
const ONLY = (argv.find(a => a.startsWith('--month=')) || '').split('=')[1]

const norm = v => String(v ?? '').replace(/\s+/g, ' ').trim()
const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0 }
const STATUS = { 'Delivery': 'DLV', 'Delivery Cancelled': 'DLV_CXL' }

function serialToDate(v) {
  const n = Number(v)
  if (!Number.isFinite(n) || n <= 0) return null
  return new Date(Date.UTC(1899, 11, 30) + Math.round(n) * 86400000).toISOString().slice(0, 10)
}

/** 월별 파일 목록 — 같은 달에 파일이 둘이면(2024-10: '-' / '_' 변형) 하나만 쓴다. */
function listFiles() {
  const byMonth = new Map()
  for (const y of YEARS) {
    const dir = path.join(ROOT, `${y}년 월간업무보고`)
    if (!fs.existsSync(dir)) continue
    for (const f of fs.readdirSync(dir)) {
      if (!/^sales analysis report.*\.xlsx$/i.test(f) || f.startsWith('~$')) continue
      const m = f.match(/(\d{4})[-_](\d{2})\.xlsx$/i)
      if (!m) continue                                   // '_total' 등 집계본 제외
      const ym = `${m[1]}-${m[2]}`
      if (!byMonth.has(ym)) byMonth.set(ym, path.join(dir, f))
    }
  }
  return [...byMonth.entries()].sort(([a], [b]) => a.localeCompare(b))
}

/** 요약 시트의 TOTAL 행 — 명세 합계 검증 기준 */
function summaryTotal(wb) {
  const sh = wb.SheetNames.find(s => /margin by customer/i.test(s))
  if (!sh) return null
  const r = XLSX.utils.sheet_to_json(wb.Sheets[sh], { header: 1, raw: true, defval: null, blankrows: false })
  const row = r.find(x => norm(x[1]) === 'TOTAL')
  if (!row) return null
  const n = v => num(String(v).replace(/,/g, ''))
  return { sales: n(row[2]), margin: n(row[3]) }
}

function parseMonth(ym, file) {
  const wb = XLSX.readFile(file, { raw: true })
  const sn = wb.SheetNames.find(s => /row.?data/i.test(s))
  if (!sn) throw new Error(`${ym}: Row_Data 시트 없음`)
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[sn], { header: 1, raw: true, defval: null, blankrows: false })
  const H = Object.fromEntries(rows[0].map((h, i) => [norm(h), i]))
  const need = ['SAP Doc. No.', 'Buyer', 'Item Code', "Q'ty", 'Unit Price (IDR)',
    'Discounted Amount (IDR)', 'P_Price(IDR)', 'Delivery Type']
  for (const k of need) if (H[k] === undefined) throw new Error(`${ym}: 컬럼 '${k}' 없음`)

  const out = []
  let skipped = 0
  const badStatus = new Set()
  for (const r of rows.slice(1)) {
    const buyer = norm(r[H['Buyer']])
    const sku = norm(r[H['Item Code']])
    if (!buyer || !sku) { skipped++; continue }          // 시트 끝의 빈 잡행(2026-02 등)
    const st = STATUS[norm(r[H['Delivery Type']])]
    if (!st) { badStatus.add(norm(r[H['Delivery Type']])); skipped++; continue }
    out.push({
      year_month: ym,
      doc_no: num(r[H['SAP Doc. No.']]),
      buyer, sku,
      brand: norm(r[H['Brand']]) || null,
      type1: norm(r[H['Type 1']]) || null,
      type2: norm(r[H['Type 2']]) || null,
      type3: norm(r[H['Type 3']]) || null,
      qty: num(r[H["Q'ty"]]),
      unit_price_idr: num(r[H['Unit Price (IDR)']]),
      unit_cost_idr: num(r[H['P_Price(IDR)']]),
      sales_idr: num(r[H['Discounted Amount (IDR)']]),
      status: st,
      delivery_date: serialToDate(r[H['Delivery Date.1']]),
      _margin: num(r[H['Margin(IDR)']]),
    })
  }
  return { rows: out, skipped, badStatus: [...badStatus], total: summaryTotal(wb), file }
}

function env() {
  const raw = fs.readFileSync(path.resolve(process.cwd(), '.env'), 'utf8')
  const get = k => (raw.match(new RegExp(`^${k}\\s*=\\s*(.+)$`, 'm')) || [])[1]?.trim().replace(/^["']|["']$/g, '')
  return { url: get('SUPABASE_URL'), key: get('SUPABASE_SERVICE_KEY') }
}

async function main() {
  let files = listFiles()
  if (ONLY) files = files.filter(([ym]) => ym === ONLY)
  console.log(`대상 ${files.length}개월 (${files[0]?.[0]} ~ ${files.at(-1)?.[0]})`)

  const parsed = []
  let bad = 0
  for (const [ym, file] of files) {
    const p = parseMonth(ym, file)
    const q = p.rows.reduce((a, r) => a + r.qty, 0)
    const s = p.rows.reduce((a, r) => a + r.sales_idr, 0)
    const mg = p.rows.reduce((a, r) => a + (r.sales_idr - r.qty * r.unit_cost_idr), 0)
    const mgSrc = p.rows.reduce((a, r) => a + r._margin, 0)
    // ① 계산 마진이 원본 Margin 열과 같은지 ② 요약 TOTAL 과 맞는지
    const dCalc = Math.abs(mg - mgSrc)
    const dS = p.total ? s - p.total.sales : null
    const dM = p.total ? mg - p.total.margin : null
    const ok = dCalc < 1 && (dS === null || Math.abs(dS) < 2) && (dM === null || Math.abs(dM) < 2)
    if (!ok) bad++
    console.log(`  ${ym} ${String(p.rows.length).padStart(5)}행` +
      ` 수량 ${q.toLocaleString().padStart(9)} 매출 ${Math.round(s).toLocaleString().padStart(18)}` +
      ` ${ok ? '✓' : `✗ 매출차 ${dS?.toFixed(2)} 마진차 ${dM?.toFixed(2)} 계산차 ${dCalc.toFixed(4)}`}` +
      (p.skipped ? ` (제외 ${p.skipped})` : '') + (p.badStatus.length ? ` ⚠status ${JSON.stringify(p.badStatus)}` : ''))
    parsed.push(p)
  }
  const totalRows = parsed.reduce((a, p) => a + p.rows.length, 0)
  console.log(`\n합계 ${totalRows.toLocaleString()}행 · 검증 실패 ${bad}개월`)
  if (bad) throw new Error('요약 대조 실패 — 적재 중단')
  if (DRY) { console.log('--dry: 적재하지 않고 종료'); return }

  const { url, key } = env()
  const sb = createClient(url, key, { auth: { persistSession: false } })
  const { data: P, error: pe } = await sb.from('sap_partners').select('id,name')
  if (pe) throw pe
  const nk = v => norm(v).toUpperCase().replace(/[.,]/g, ' ').replace(/\s+/g, ' ').trim()
  const pid = new Map(P.map(r => [nk(r.name), r.id]))

  for (const p of parsed) {
    const ym = p.rows[0]?.year_month
    if (!ym) continue
    const { error: de } = await sb.from('margin_lines').delete().eq('year_month', ym)
    if (de) throw new Error(`${ym} delete: ${de.message}`)
    const payload = p.rows.map(r => {
      const id = pid.get(nk(r.buyer))
      if (!id) throw new Error(`${ym}: 거래처 미매칭 '${r.buyer}'`)
      const { buyer, _margin, ...rest } = r
      return { ...rest, partner_id: id }
    })
    for (let i = 0; i < payload.length; i += 1000) {
      const { error } = await sb.from('margin_lines').insert(payload.slice(i, i + 1000))
      if (error) throw new Error(`${ym} @${i}: ${error.message}`)
    }
    process.stdout.write(`\r  적재 ${ym} (${payload.length}행)   `)
  }
  console.log('\n완료')
}

main().catch(e => { console.error('\n실패:', e.message); process.exit(1) })
