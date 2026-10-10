// 자료실 문서 1건 등록 — Storage 업로드 + doc_posts insert 를 한 번에.
//
//   node scripts/upload-doc.mjs <scope> "<title>" "<category>" <YYYY-MM-DD> <local.html>
//   scope = company | personal
//
// 같은 파일명이 이미 등록돼 있으면 본문만 교체하고 updated_on 을 오늘(WIB)로 갱신한다.
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { serviceCreds } from './_env.mjs';

const [scope, title, category, publishedOn, localPath] = process.argv.slice(2);
if (!['company', 'personal'].includes(scope) || !title || !category || !/^\d{4}-\d{2}-\d{2}$/.test(publishedOn ?? '') || !localPath) {
  console.error('사용법: node scripts/upload-doc.mjs <company|personal> "<제목>" "<분류>" <YYYY-MM-DD> <local.html>');
  process.exit(1);
}
const { url, key } = serviceCreds();
if (!url || !key) { console.error('✗ .env 에 SUPABASE_URL / SUPABASE_SERVICE_KEY 가 필요합니다.'); process.exit(1); }
const sb = createClient(url, key, { auth: { persistSession: false } });

const file = basename(localPath);
const body = readFileSync(localPath);
const path = `${scope}/${file}`;

const up = await sb.storage.from('docs').upload(path, body, { contentType: 'text/html; charset=utf-8', upsert: true });
if (up.error) { console.error('✗ 업로드 실패:', up.error.message); process.exit(1); }

const today = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);   // WIB 날짜
const { data: exist } = await sb.from('doc_posts').select('id').eq('file', file).maybeSingle();
const res = exist
  ? await sb.from('doc_posts').update({ title, category, scope, updated_on: today }).eq('id', exist.id)
  : await sb.from('doc_posts').insert({ title, category, scope, published_on: publishedOn, file });
if (res.error) { console.error('✗ doc_posts 반영 실패:', res.error.message); process.exit(1); }
console.log(`✓ ${path} (${body.length} bytes) · doc_posts ${exist ? '수정' : '등록'}`);
