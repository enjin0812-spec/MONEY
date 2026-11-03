-- =====================================================================
-- 가계부 DB 업데이트 v2 (schema.sql 다음에 실행. 여러 번 실행해도 안전)
-- 카테고리 그룹·화면 설정, 세부 카테고리·태그, 계좌 연동, 반복 거래, 회원 탈퇴
-- =====================================================================

-- ---------- 설정: 사용자 정의 그룹 + 화면 설정 ----------
alter table public.settings add column if not exists groups jsonb not null default '[]'::jsonb;
alter table public.settings add column if not exists prefs  jsonb not null default '{}'::jsonb;

-- ---------- 계좌: 잔액 입력 시각 (이후 거래가 잔액에 반영됨) ----------
alter table public.accounts add column if not exists balance_at timestamptz not null default now();

-- ---------- 고정·반복 거래 ----------
alter table public.fixed_costs add column if not exists type text not null default 'expense';
alter table public.fixed_costs add column if not exists sub text not null default '';
alter table public.fixed_costs add column if not exists account_id uuid references public.accounts(id) on delete set null;
alter table public.fixed_costs add column if not exists to_account_id uuid references public.accounts(id) on delete set null;
alter table public.fixed_costs add column if not exists auto boolean not null default false;
alter table public.fixed_costs add column if not exists start_month text;
alter table public.fixed_costs add column if not exists last_month text;
alter table public.fixed_costs add column if not exists tags text[] not null default '{}';
do $$ begin
  alter table public.fixed_costs add constraint fixed_costs_type_chk check (type in ('income','expense','saving','invest','transfer'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.fixed_costs add constraint fixed_costs_month_chk check ((start_month is null or start_month ~ '^\d{4}-\d{2}$') and (last_month is null or last_month ~ '^\d{4}-\d{2}$') and char_length(sub) <= 40 and cardinality(tags) <= 5);
exception when duplicate_object then null; end $$;

-- ---------- 거래: 세부 카테고리, 태그, 계좌, 반복 거래 연결 ----------
alter table public.transactions add column if not exists sub text not null default '';
alter table public.transactions add column if not exists tags text[] not null default '{}';
alter table public.transactions add column if not exists account_id uuid references public.accounts(id) on delete set null;
alter table public.transactions add column if not exists to_account_id uuid references public.accounts(id) on delete set null;
alter table public.transactions add column if not exists recurring_id uuid references public.fixed_costs(id) on delete set null;
do $$ begin
  alter table public.transactions add constraint transactions_extra_chk check (char_length(sub) <= 40 and cardinality(tags) <= 5);
exception when duplicate_object then null; end $$;
-- 같은 반복 거래가 같은 달에 두 번 기록되지 않도록
create unique index if not exists transactions_recurring_month on public.transactions (recurring_id, month) where recurring_id is not null;

-- ---------- 연결 대상이 본인 소유인지 확인 (남의 계좌·반복 거래 ID 연결 차단) ----------
create or replace function public.check_owned_refs()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.account_id is not null and not exists (select 1 from public.accounts where id = new.account_id and user_id = new.user_id) then
    raise exception 'account not found';
  end if;
  if new.to_account_id is not null and not exists (select 1 from public.accounts where id = new.to_account_id and user_id = new.user_id) then
    raise exception 'account not found';
  end if;
  if tg_table_name = 'transactions' then
    if new.recurring_id is not null and not exists (select 1 from public.fixed_costs where id = new.recurring_id and user_id = new.user_id) then
      raise exception 'recurring item not found';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists transactions_owned_refs on public.transactions;
create trigger transactions_owned_refs before insert or update on public.transactions
  for each row execute function public.check_owned_refs();
drop trigger if exists fixed_costs_owned_refs on public.fixed_costs;
create trigger fixed_costs_owned_refs before insert or update on public.fixed_costs
  for each row execute function public.check_owned_refs();

-- ---------- 새 가입자 기본값: 누구에게나 무난한 카테고리 (모두 수정·삭제 가능) ----------
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

-- ---------- 회원 탈퇴: 본인 계정과 모든 데이터 삭제 ----------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- 이전 버전 계정도 새 기능이 동작하도록 기본값 채우기 (기존 데이터는 그대로)
update public.fixed_costs set start_month = to_char(created_at, 'YYYY-MM') where start_month is null;
