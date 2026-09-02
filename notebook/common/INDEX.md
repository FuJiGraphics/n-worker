# common 인덱스 (스택 무관)

> 어느 코드베이스에서도 사실인 지식만 둔다. 스택 종속(엔진/프레임워크)은 stacks/ 로, 프로젝트 종속은 projects/ 로.

## model-routing - [model-routing.md](model-routing.md)
> **서브를 스폰하기 직전에 본다**(P1 조사, P2 렌즈, P3 위임 생산, curator 전부). 모델 티어와 effort 배치의 단일 근거 + 현재 세대 매핑. 파일 머리의 갱신 트리거가 걸리면(세션 모델이 표에 없다 / checked 60일 초과) curator 를 `model-refresh` 모드로 스폰해 갱신한다.

## report-conventions - [report-conventions.md](report-conventions.md)
> P5 보고서를 만들 때 본다. 저장 위치, 파일명 관례. 항목이 비면 첫 보고서 때 사용자에게 묻고 curator 가 채운다.

## harness-routing - [harness-routing.md](harness-routing.md)
> 이 스킬이 관측 기반으로 기댄 하네스(Claude Code) 동작 목록 - 항목마다 가정, 사용 위치, 근거, 깨졌을 때 폴백. nb-load 가 `checked_version` 과 현재 버전을 비교해 다르면 알린다 → curator `harness-refresh`. curator 데몬 권한 모드의 근거는 #1.

## lessons - [lessons-index.md](lessons-index.md)
> 이번 작업에 도구 함정/일반 원칙류가 걸릴 것 같으면 펼친다. 기록이 쌓여 인덱스가 커지면 curator 가 도메인별로 분리한다.

## scripts - [scripts/INDEX.md](scripts/INDEX.md)
> 범용 재사용 스크립트(파일 이동/일괄 치환/집계 등 bash, python).
