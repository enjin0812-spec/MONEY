-- =====================================================================
-- 가계부 DB 설정 (Supabase SQL Editor에 전체 붙여넣고 Run)
-- 여러 번 실행해도 안전하게 작성됨. 개인정보·샘플 데이터 없음.
-- =====================================================================

-- ---------- 1. 테이블 ----------
create table if not exists public.settings (
  user_id      uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  expense_cats jsonb  not null default '[]'::jsonb,
  income_cats  jsonb  not null default '[]'::jsonb,
  base_budget  jsonb  not null default '{}'::jsonb,
  month_budget jsonb  not null default '{}'::jsonb,
  total_budget bigint not null default 0 check (total_budget >= 0),
  updated_at   timestamptz not null default now()
);

create table if not exists public.transactions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type       text not null check (type in ('income','expense','saving','invest','transfer')),
  unit       text not null default 'day' check (unit in ('day','month')),
  date       date,
  month      text not null check (month ~ '^\d{4}-\d{2}$'),
  amount     bigint not null check (amount > 0),
  category   text not null default '' check (char_length(category) <= 40),
  title      text not null default '' check (char_length(title) <= 80),
  method     text not null default '' check (char_length(method) <= 40),
  memo       text not null default '' check (char_length(memo) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((unit = 'day' and date is not null) or (unit = 'month' and date is null))
);
create index if not exists transactions_user_month on public.transactions (user_id, month);

create table if not exists public.accounts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('계좌','카드')),
  name        text not null check (char_length(name) between 1 and 40),
  institution text not null default '' check (char_length(institution) <= 40),
  purpose     text not null default '' check (char_length(purpose) <= 20),
  balance     bigint not null default 0,
  link        text not null default '' check (char_length(link) <= 40),
  memo        text not null default '' check (char_length(memo) <= 120),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists accounts_user on public.accounts (user_id);

create table if not exists public.fixed_costs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  category   text not null default '' check (char_length(category) <= 40),
  day        int check (day between 1 and 31),
  amount     bigint not null check (amount > 0),
  active     boolean not null default true,
  memo       text not null default '' check (char_length(memo) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fixed_costs_user on public.fixed_costs (user_id);

create table if not exists public.plans (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  type       text not null check (type in ('저축','투자')),
  target     bigint not null default 0 check (target >= 0),
  memo       text not null default '' check (char_length(memo) <= 160),
  sort       int not null default 99,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);
create index if not exists plans_user on public.plans (user_id);

-- ---------- 2. Row Level Security: 본인 행만 조회·추가·수정·삭제 ----------
do $$
declare t text;
begin
  foreach t in array array['settings','transactions','accounts','fixed_costs','plans'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('drop policy if exists own_select on public.%I', t);
    execute format('drop policy if exists own_insert on public.%I', t);
    execute format('drop policy if exists own_update on public.%I', t);
    execute format('drop policy if exists own_delete on public.%I', t);
    execute format('create policy own_select on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t);
    execute format('create policy own_insert on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t);
    execute format('create policy own_update on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
    execute format('create policy own_delete on public.%I for delete to authenticated using ((select auth.uid()) = user_id)', t);
    -- 로그인하지 않은 요청(anon)은 테이블 접근 자체를 차단
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ---------- 3. 가입 시 빈 대시보드 + 기본 카테고리 자동 생성 ----------
alter table public.settings add column if not exists groups jsonb not null default '[]'::jsonb;
alter table public.settings add column if not exists prefs  jsonb not null default '{}'::jsonb;
create or replace function public.create_default_book(uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.settings (user_id, groups, expense_cats, income_cats, prefs)
  values (uid,
    '[{"id":"g1","name":"생활비"},{"id":"g2","name":"고정지출"},{"id":"g3","name":"여가·기타"}]'::jsonb,
    '[{"name":"식비","group":"g1","color":"#e0855b","subs":[]},{"name":"카페·간식","group":"g1","color":"#c9a03c","subs":[]},
      {"name":"생활용품","group":"g1","color":"#4fae7f","subs":[]},{"name":"교통","group":"g1","color":"#3fa3b8","subs":[]},
      {"name":"의료·건강","group":"g1","color":"#d65b7a","subs":[]},
      {"name":"주거·관리비","group":"g2","color":"#5b7be0","subs":[]},{"name":"통신","group":"g2","color":"#9a6bd6","subs":[]},
      {"name":"보험","group":"g2","color":"#6c8f3a","subs":[]},{"name":"구독","group":"g2","color":"#b46f3c","subs":[]},
      {"name":"쇼핑","group":"g3","color":"#d1785f","subs":[]},{"name":"문화·여가","group":"g3","color":"#5f6fd1","subs":[]},
      {"name":"경조사·선물","group":"g3","color":"#c45fa0","subs":[]},{"name":"교육","group":"g3","color":"#3c8c8c","subs":[]},
      {"name":"기타","group":"g3","color":"#8c94a6","subs":[]}]'::jsonb,
    '[{"name":"급여","color":"#5b7be0"},{"name":"부수입","color":"#4fae7f"},{"name":"용돈","color":"#c9a03c"},{"name":"금융수익","color":"#9a6bd6"},{"name":"기타","color":"#8c94a6"}]'::jsonb,
    '{"monthStart":1}'::jsonb)
  on conflict (user_id) do nothing;
end $$;
revoke all on function public.create_default_book(uuid) from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.create_default_book(new.id);
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 이 SQL을 실행하기 전에 이미 가입한 계정이 있으면 기본값 채우기
select public.create_default_book(id) from auth.users;
