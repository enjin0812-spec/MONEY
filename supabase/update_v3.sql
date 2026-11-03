-- =====================================================================
-- 가계부 DB 업데이트 v3 (update_v2.sql 다음에 실행. 여러 번 실행해도 안전)
-- 카드 할부, 대출(부채) 계좌, 목표 저축
-- =====================================================================

-- ---------- 할부: 같은 할부 묶음 표시 ----------
alter table public.transactions add column if not exists inst_id uuid;
alter table public.transactions add column if not exists inst_no int;
alter table public.transactions add column if not exists inst_total int;
do $$ begin
  alter table public.transactions add constraint transactions_inst_chk check (
    (inst_id is null and inst_no is null and inst_total is null)
    or (inst_id is not null and inst_total between 2 and 60 and inst_no between 1 and inst_total));
exception when duplicate_object then null; end $$;
create index if not exists transactions_inst on public.transactions (inst_id) where inst_id is not null;

-- ---------- 대출(부채) 계좌 종류 추가 ----------
alter table public.accounts drop constraint if exists accounts_kind_check;
alter table public.accounts add constraint accounts_kind_check check (kind in ('계좌','카드','대출'));

-- ---------- 목표 저축: 목표 금액·날짜·이미 모은 금액 ----------
alter table public.plans add column if not exists goal bigint not null default 0;
alter table public.plans add column if not exists goal_date date;
alter table public.plans add column if not exists saved_base bigint not null default 0;
do $$ begin
  alter table public.plans add constraint plans_goal_chk check (goal >= 0 and saved_base >= 0);
exception when duplicate_object then null; end $$;
