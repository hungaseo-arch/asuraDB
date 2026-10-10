// public/docs/*.html → Supabase Storage(private 버킷 `docs`) 이전 + 크기 검증
//
//   node scripts/migrate_docs_to_storage.mjs --dry   # 계획만 출력
//   node scripts/migrate_docs_to_storage.mjs         # 업로드 + 다운로드 검증
//
// 객체 경로: docs/<scope>/<file> (doc_posts 행) · docs/templates/<file> (목록 미등록 템플릿)
// service_role 키는 .env 에서 읽으며 출력하지 않는다.
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { serviceCreds } from './_env.mjs';

const DRY = process.argv.includes('--dry');
const SRC = new URL('../public/docs/', import.meta.url);
const BUCKET = 'docs';
const TEMPLATES = ['phrasal-verbs-deck-200.html'];

const { url, key } = serviceCreds();
if (!url || !key) { console.error('✗ .env 에 SUPABASE_URL / SUPABASE_SERVICE_KEY 가 필요합니다.'); process.exit(1); }
const sb = createClient(url, key, { auth: { persistSession: false } });

const { data: rows, error } = await sb.from('doc_posts').select('id,scope,file').order('id');
if (error) { console.error('✗ doc_posts 조회 실패:', error.message); process.exit(1); }

const jobs = [
  ...rows.map((r) => ({ id: r.id, path: `${r.scope}/${r.file}`, local: r.file })),
  ...TEMPLATES.map((f) => ({ id: '-', path: `templates/${f}`, local: f })),
];

const report = [];
for (const j of jobs) {
  const fileUrl = new URL(j.local, SRC);
  if (!existsSync(fileUrl)) { report.push({ ...j, status: 'SKIP(원본 없음)' }); continue; }
  const body = readFileSync(fileUrl);
  if (DRY) { report.push({ ...j, local_bytes: body.length, status: 'DRY' }); continue; }
  const up = await sb.storage.from(BUCKET).upload(j.path, body, { contentType: 'text/html; charset=utf-8', upsert: true });
  if (up.error) { report.push({ ...j, local_bytes: body.length, status: `UPLOAD FAIL: ${up.error.message}` }); continue; }
  const dl = await sb.storage.from(BUCKET).download(j.path);
  const remote = dl.error ? -1 : (await dl.data.arrayBuffer()).byteLength;
  report.push({ ...j, local_bytes: body.length, remote_bytes: remote, status: remote === body.length ? 'OK' : 'SIZE MISMATCH' });
}

console.table(report.map(({ id, path, local_bytes, remote_bytes, status }) => ({ id, path, local_bytes, remote_bytes, status })));
const ok = report.filter((r) => r.status === 'OK').length;
const skipped = report.filter((r) => r.status.startsWith('SKIP')).length;
console.log(`doc_posts ${rows.length}행 · 업로드 성공 ${ok} · 원본 없음 ${skipped} · 템플릿 ${TEMPLATES.length}`);
if (!DRY && report.some((r) => !['OK'].includes(r.status) && !r.status.startsWith('SKIP'))) process.exit(1);
