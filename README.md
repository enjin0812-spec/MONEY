# 가계부

수입·지출, 계좌·카드, 월 예산, 저축·투자, 고정비·구독, 연간 결산을 관리하는 다중 사용자 가계부.

- 화면: `index.html` (정적 파일, GitHub Pages로 배포)
- 로그인·데이터: Supabase (이메일 가입, Row Level Security로 사용자별 데이터 격리)
- DB 설정: `supabase/schema.sql`을 Supabase SQL Editor에서 한 번 실행

## 데이터 보호
- 모든 테이블에 `user_id` 소유권 + RLS(본인 행만 조회·추가·수정·삭제), 로그인하지 않은 요청은 차단
- 가입 시 DB 트리거가 빈 설정과 기본 카테고리를 자동 생성
- 사이트에 들어 있는 키는 공개용(publishable) 키뿐이며, secret key는 저장소에 넣지 않음
- 계좌번호·카드번호 입력란 없음, 개인 데이터·샘플 데이터 없음
