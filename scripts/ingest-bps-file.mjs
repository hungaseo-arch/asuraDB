// BPS EXIM XLSX → Supabase tire_imports 적재 (수동/무키 B안)
//
// BPS WebAPI 키 없이 운영하는 경로:
//   1) https://www.bps.go.id/id/exim 접속 → 수입(Impor)·연도·HS 32종·월 선택 → 교차표 생성
//   2) US$ (Nilai) 표 → 엑셀 다운로드    (metric=value)
//      KG (Berat Bersih) 표 → 엑셀 다운로드 (metric=weight, 선택)
//   3) 이 스크립트로 적재:
//        node scripts/ingest-bps-file.mjs <파일.xlsx> [옵션]
//
// 옵션:
//   --metric=value|weight   기본 value (US$). weight = netweight KG 표
//   --year=YYYY             파일에 연도 컬럼이 없을 때 폴백
//   --all                   국가별 대신 전체(ALL)로만 집계
//   --dry-run | -n          DB 적재 없이 미리보기
//
// 예:
//   node scripts/ingest-bps-file.mjs ~/Downloads/exim_2025_nilai.xlsx --dry-run
//   node scripts/ingest-bps-file.mjs ~/Downloads/exim_2025_nilai.xlsx
//   node scripts/ingest-bps-file.mjs ~/Downloads/exim_2025_berat.xlsx --metric=weight
//
// value/weight 는 buildUpsertPayload 가 기존 DB 값과 병합 → 한쪽 적재가 다른쪽을 0으로 덮지 않음.
// service_role 키는 .env 의 SUPABASE_SERVICE_KEY 에서 읽음 (create_auth_users.mjs 와 동일 관례).

import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { parseBpsWorkbook, buildUpsertPayload } from './bps-parser.mjs';
import { serviceCreds } from './_env.mjs';

// ── .env 로드 (공유 로더) ─────────────────────────────────────────
const { url: SB_URL, key: SERVICE_KEY } = serviceCreds();
if (!SB_URL)      { console.error('✗ .env에 SUPABASE_URL / VITE_SB_URL 이 없습니다.'); process.exit(1); }
if (!SERVICE_KEY) { console.error('✗ service_role 키 없음 (.env SUPABASE_SERVICE_KEY).'); process.exit(1); }

// ── 국가 표기 정규화 (BPS 파일 표기 → 기존 DB 영문 표기) ─────────
// country 는 UNIQUE 키의 일부 — 기존 수동입력 표기와 다르면 별도 행으로 갈라지므로 여기서 통일.
// 단일 소스: data/country_alias.json — collectors/bps_import_collector.py 와 공유(드리프트 방지).
const COUNTRY_ALIAS = Object.fromEntries(
  Object.entries(JSON.parse(readFileSync(new URL('../data/country_alias.json', import.meta.url), 'utf8')))
    .filter(([k]) => !k.startsWith('_')),
);
const aliasCI = Object.fromEntries(Object.entries(COUNTRY_ALIAS).map(([k, v]) => [k.toUpperCase(), v]));
// 미등록 국가는 Python 수집기(raw_ctr.title())와 동일하게 Title Case 로 폴백해 표기를 일치시킨다.
// 단 'ALL'(합계)·'Totals'는 그대로 유지.
const titleCase = (s) => s.toLowerCase().replace(/\b[\p{L}]/gu, (m) => m.toUpperCase());
const normCountry = (c) => {
  if (c === 'ALL' || c === 'Totals') return c;
  return aliasCI[String(c).toUpperCase()] ?? titleCase(String(c));
};
// parseBpsWorkbook 는 countryAlias[c] || c 로 조회 → normCountry 를 get 으로 노출하는 Proxy.
const aliasProxy = new Proxy({}, { get: (_, k) => normCountry(String(k)) });

// ── 인자 파싱 ────────────────────────────────────────────────────
const argv   = process.argv.slice(2);
const files  = argv.filter((a) => !a.startsWith('-'));
const opt    = (name) => argv.find((a) => a.startsWith(`--${name}=`))?.split('=')[1];
const metric = opt('metric') ?? 'value';
const year   = opt('year') ? parseInt(opt('year'), 10) : null;
const byCountry = !argv.includes('--all');
const dryRun = argv.includes('--dry-run') || argv.includes('-n');

if (!files.length) {
  console.error('사용법: node scripts/ingest-bps-file.mjs <BPS_EXIM.xlsx> [--metric=value|weight] [--year=YYYY] [--all] [--dry-run]');
  process.exit(1);
}
if (!['value', 'weight'].includes(metric)) {
  console.error(`✗ --metric 은 value|weight 만 가능: ${metric}`); process.exit(1);
}

const sb = createClient(SB_URL, SERVICE_KEY);
const fmt = (n) => Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 });

for (const file of files) {
  console.log(`\n[ingest-bps] ${file}  (metric=${metric}${byCountry ? '' : ', ALL 집계'}${dryRun ? ', dry-run' : ''})`);

  // 1) 파싱
  const buf = readFileSync(file);
  let parsed;
  try {
    parsed = parseBpsWorkbook(new Uint8Array(buf), { metric, byCountry, year, countryAlias: aliasProxy });
  } catch (e) {
    console.error(`✗ 파싱 실패: ${e.message}`); process.exitCode = 1; continue;
  }
  const { rows, countries, skipped, hsFound } = parsed;
  if (!rows.length) { console.error('✗ 변환된 행이 없습니다. (표 구조/HS 코드 확인)'); process.exitCode = 1; continue; }

  // 2) 요약 출력
  const years  = [...new Set(rows.map((r) => r.year))].sort();
  const months = [...new Set(rows.map((r) => r.month))].sort((a, b) => a - b);
  const key = metric === 'value' ? 'value_usd' : 'weight_kg';
  const byCat = {};
  for (const r of rows) byCat[r.category] = (byCat[r.category] ?? 0) + (r[key] ?? 0);
  console.log(`  · ${rows.length}행 · 연도 ${years.join(',')} · 월 ${months[0]}~${months.at(-1)} · HS ${hsFound.length}종 · 국가 ${countries.length}개`);
  if (skipped.length) console.log(`  · 마스터 미등록 HS 건너뜀: ${skipped.join(', ')}`);
  for (const [cat, v] of Object.entries(byCat).sort((a, b) => b[1] - a[1]))
    console.log(`      ${cat.padEnd(13)} ${metric === 'value' ? '$' : ''}${fmt(v)}${metric === 'weight' ? ' kg' : ''}`);
  const aliasTargets = new Set(Object.values(COUNTRY_ALIAS));
  // 별칭에 없어 Title Case 폴백으로 저장된 국가 — 기존 DB 표기와 다르면 갈라질 수 있어 경고.
  const unmapped = countries.filter((c) => c !== 'ALL' && !aliasTargets.has(c));
  if (unmapped.length) console.log(`  ⚠ 별칭 미등록 국가(Title Case 폴백 저장): ${unmapped.join(', ')}\n    → 기존 DB 표기와 다르면 data/country_alias.json 에 추가 후 재실행`);

  if (dryRun) { console.log(`  [dry-run] 적재 생략 (미리보기 상위 3행):`); console.table(rows.slice(0, 3)); continue; }

  // 3) 기존 행 조회 → 병합 (value/weight 상호 보존)
  //    PostgREST 기본 1000행 캡 회피 — .range() 로 페이지네이션해 전체 수집(1년치 >1000행).
  const existing = [];
  let selErr = null;
  for (let from = 0; ; from += 1000) {
    const { data, error } = await sb
      .from('tire_imports')
      .select('year,month,hs_code,country,value_usd,weight_kg')
      .in('hs_code', hsFound)
      .in('year', years)
      .range(from, from + 999);
    if (error) { selErr = error; break; }
    existing.push(...(data ?? []));
    if (!data || data.length < 1000) break;
  }
  if (selErr) { console.error(`✗ 기존 행 조회 실패: ${selErr.message}`); process.exitCode = 1; continue; }
  const payload = buildUpsertPayload(rows, existing);

  // 4) upsert (200행 배치)
  let done = 0;
  for (let i = 0; i < payload.length; i += 200) {
    const { error } = await sb
      .from('tire_imports')
      .upsert(payload.slice(i, i + 200), { onConflict: 'year,month,hs_code,country' });
    if (error) {
      console.error(`✗ upsert 실패 (${i}~): ${error.message}`);
      if (/violates check constraint/.test(error.message))
        console.error('  → alter_categories_v3.sql(최신 category CHECK)을 Supabase 에 먼저 적용했는지 확인하세요.');
      process.exitCode = 1; done = -1; break;
    }
    done += Math.min(200, payload.length - i);
  }
  if (done >= 0) console.log(`  ✓ ${done}행 upsert 완료 (기존 ${existing?.length ?? 0}행과 병합)`);
}
