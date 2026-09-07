# common 인덱스 (스택 무관)

> 어느 코드베이스에서도 사실인 지식만 둔다. 스택 종속(엔진/프레임워크)은 stacks/ 로, 프로젝트 종속은 projects/ 로.

## model-routing - [model-routing.md](model-routing.md)
> **서브를 스폰하기 직전에 본다**(P1 조사, 리뷰어, P3 위임 생산, curator 전부). 모델 티어와 effort 배치의 단일 근거 + 현재 세대 매핑. 파일 머리의 갱신 트리거가 걸리면(세션 모델이 표에 없다 / 별칭 거부) curator 를 `model-refresh` 모드로 큐에 넣어 갱신한다.

## report-conventions - [report-conventions.md](report-conventions.md)
> P5 보고서를 만들 때 본다. 저장 위치, 파일명 관례, 이 환경의 pdf 변환 도구 경로.

## harness-routing - [harness-routing.md](harness-routing.md)
> 이 스킬이 관측 기반으로 기댄 하네스(Claude Code) 동작 목록 - 항목마다 가정, 사용 위치, 근거, 깨졌을 때 폴백. nb-load 가 `checked_version` 과 현재 버전을 비교해 다르면 알린다(정보). 실제로 깨진 동작이 있을 때 curator `harness-refresh`. curator 데몬 권한 모드의 근거는 #1.

## lessons - 한줄 목록은 3파일 (2026-08-20 2분할, 2026-09-03 3분할, 라우터는 [lessons-index.md](lessons-index.md))
> 이번 작업에 도구 함정/일반 원칙류가 걸릴 것 같으면 해당 쪽만 펼친다.
> 함정 [lessons-index-gotchas.md](lessons-index-gotchas.md) - 반복해 당한 것, 증상이 먼저 오는 것.
> 운영 [lessons-index-infra.md](lessons-index-infra.md) - **도구, 검증, 워크플로 운영(파이프, SIGPIPE 로 잘리는 부수효과, 세션 마커, 상태 파일, $WORK 증발, 핸들 정규화, 셸 문법 검사와 지연 파싱, fail-open 게이트 검증, 서브 입력 원문성, 병렬 팬아웃 부분 실패와 세션 한도, Workflow args, 서브 결과의 메인 재적재, 팬아웃 단위)**.
> 결정, 패턴 [lessons-index-decisions.md](lessons-index-decisions.md) - 설계 결정(매번 이렇게 정한다) + 작업 패턴(이렇게 하면 빠르다).

## scripts - [scripts/INDEX.md](scripts/INDEX.md)
> 범용 재사용 스크립트(파일 이동/일괄 치환/집계 등 bash, python).
