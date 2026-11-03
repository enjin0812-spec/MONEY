-- =====================================================================
-- 가계부 DB 업데이트 v4: 일시정지 방지용 신호 함수 (여러 번 실행해도 안전)
-- 데이터를 읽거나 쓰지 않고 숫자 1만 돌려줌. 누구의 기록에도 접근하지 않음.
-- =====================================================================
create or replace function public.keepalive()
returns int language sql stable set search_path = public as $$ select 1 $$;
revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;
