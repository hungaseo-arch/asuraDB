-- 2026-07-01 — '정리' 게시판 문서 메타데이터 테이블
-- HTML 본문은 public/docs/<file> 정적 자산, 이 테이블은 목록/검색/분류용 메타만 보관.
create table if not exists public.doc_posts (
  id            bigint generated always as identity primary key,
  title         text not null,
  category      text not null default '기타',
  published_on  date not null default current_date,
  file          text not null unique,          -- public/docs/<file>.html
  sort_order    int  not null default 0,
  created_at    timestamptz not null default now()
);

alter table public.doc_posts enable row level security;

-- 로그인 사용자(JWT) 읽기 허용 (가이드 §11: to authenticated + 사용자 JWT)
drop policy if exists "doc_posts read authenticated" on public.doc_posts;
create policy "doc_posts read authenticated"
  on public.doc_posts for select
  to authenticated
  using (true);

create index if not exists doc_posts_published_idx
  on public.doc_posts (published_on desc);

-- 시드: 기존 문서 1건
insert into public.doc_posts (title, category, published_on, file)
values ('재고·Buffer Stock 적정성 검토 산식 작성 가이드', '재고량 산정', '2026-06-25', 'buffer_stock_review.html')
on conflict (file) do nothing;
