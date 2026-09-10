# 위험 기반 리뷰 - 실제 변경과 실행 결과 확인

> **사용자가 리뷰를 요청했을 때만 읽고 실행한다.** 스킬이 자발적으로 리뷰어를 투입하지 않는다(2026-09-10 사용자 결정). 요청이 없으면 P4 의 검증은 자동 검증 + 메인의 diff 확인으로 끝난다.

## 0. 투입 기준과 예산

리뷰는 자동 검증이 놓칠 중요한 변경을 확인하는 수단이다. 파일 수가 아니라 동작, 공유 계약, 실패 비용으로 정한다.

| 위험 | 기준 | 기본 투입 |
|---|---|---|
| 낮음 | 국소 변경, 외부/공유 계약 영향 없음, 관련 자동 검증으로 덮임 | 별도 리뷰어 없음, 메인이 diff 확인 |
| 일반 | 동작 변경 또는 여러 구성요소의 연결 변경 | 통합 리뷰어 1명 |
| 높음 | 데이터 이행, 공개 API/보안/금전, 복구 어려운 쓰기, 복잡한 비동기 수명 | 통합 리뷰어 1명 + 필요한 전문 리뷰어 1명까지 |

- 노트북 인덱스가 위험 판정 재료에 들어간다: 대상 시스템의 lessons 밀도(함정 밀집 = 상향), facts 불변 항목 저촉(상향).
- 작업당 최초 리뷰어는 최대 2명이다. P2의 사전 설계 리뷰가 있으면 여기에 포함한다. 추가 투입은 실제로 남은 위험과 비용을 설명하고 사용자 승인을 받는다.
- 일반 작업의 리뷰 시점은 P4다. P3 구현과 컴파일/관련 테스트를 끝내고 실제 diff를 준다. 이미 실패 원인이 명확한 컴파일 오류를 리뷰어에게 조사시키지 않는다.
- P2 설계 리뷰는 되돌리기 어려운 변경의 계약/이행/복구에 불확실성이 있을 때만 1명 사용한다. P4에서는 그 설계 자체가 아니라 실제 구현에서 달라진 위험을 확인한다.
- 리뷰어는 명세가 지정한 위험과 변경 지점에 집중하고 중요한 지적 최대 5건을 반환한다. 추가 조사가 필요하면 확인한 결과와 `unverified`를 돌려줘 메인이 추가 비용을 판단하게 한다.
- 이미 확인한 근거는 재사용한다. 지적 수정 확인은 같은 에이전트에 변경분만 보내 1회 수행한다. 이어쓰기가 불가능하면 좁은 명세와 기존 근거를 전달한다. 예산 초과로 자동 재분할/전체 재실행하지 않는다.

## 1. 역할과 입력

### 통합 리뷰어

실제 변경이 요청한 동작과 기존 계약을 지키는지 확인한다. 진입점 연결, 기존 호출자에 미치는 영향, 그리고 기존 구조와 컨벤션 이탈(우회 진입점, 중복 시스템, 새 헬퍼 양산, 요구 대비 과한 변경)을 본다. 실행 결과가 증명하는 범위와 증명하지 못하는 범위를 구분한다. 문제 없으면 지적 0건이 정상이다.

### 전문 리뷰어

고위험 표면 한 가지를 구체적으로 맡긴다. 예: 구버전 저장 데이터 로드/변환, 이벤트 구독과 비동기 취소, 외부 쓰기의 부분 실패/재실행, 보안 경계. 통합 리뷰어와 같은 파일 전체를 같은 질문으로 다시 보지 않는다.

### 정합성 확인 범위

새로 추가/변경한 문자열 키, 데이터 값, 리소스 경로, 직렬화 참조와 실제 소비처의 연결만 확인한다. 같은 소스와 어셈블리를 대상으로 통과한 컴파일/타입 검사 결과가 있으면 시그니처와 멤버 존재 여부는 그 결과를 사용한다. 컴파일 불가 또는 reflection/동적 로딩처럼 검사 밖인 계약은 해당 항목만 직접 대조하고 나머지 미검증 범위를 남긴다. 에셋 쓰기는 저장된 결과와 참조 대상을 확인한다.

### 전달할 것

- `$WORK/plan.md`의 목표, 범위, 계약 절 경로
- 프로젝트 루트, 변경 파일 목록, **세션 변경분만 담은 diff 파일 경로**
- 실행한 컴파일/테스트의 명령, 범위, 결과 경로와 미검증 부분
- 필요한 프로젝트 지침, 이번 작업과 관련된 노트북 lessons 경로 목록("이 기록들을 먼저 읽고 대조하라 - 과거에 검증된 함정이다"), `$WORK`와 nb-grep 호출법, 수용된 리스크
- 맡긴 질문, 예산, 반환 schema

서브는 대화를 상속하지 않는다. 실제 파일은 필요한 절만 읽는다. 생산 서브가 자기 구현의 유일한 리뷰어가 되지는 않게 한다. P2 설계 검토에서는 diff 대신 합의할 계약과 변경 방향을 제공한다.

## 2. 지적 처리

- `critical`: 실제 변경이 실행 오류, 요구 동작 위반, 보안/데이터 손실, 중요한 회귀를 만드는 근거가 있음. 해당 코드/데이터 위치와 발생 조건을 함께 제시한다.
- `concern`: 결과가 달라지는 트레이드오프 또는 확인이 필요한 위험. 단순한 개인 취향은 제외한다.
- `minor`: 수정이 필요하지만 비차단인 국소 문제. 줄번호 한 칸 이동, 칭찬, 문서 형식 채우기는 지적으로 만들지 않는다.
- 근거가 없는 가능성이나 확인하지 못한 범위는 `unverified`다. 초안의 설명 생략을 실제 코드 결함과 동일하게 분류하지 않는다.
- 메인은 중복 지적을 합치고, 고위험/모순/근거 부족 항목만 라이브 확인한다. 사소한 수정은 기존 범위 안에서 처리하고 전체 P1/P2로 되돌아가지 않는다.
- 사용자 의도, 공개 계약, 범위가 바뀔 때만 다시 질문한다. 재검증은 변경된 근거와 영향을 받는 검사에 한정한다.
- `findings: []`만으로 완료가 아니다. `status: complete`, `unverified: []`, 요청한 범위를 실제로 확인했는지를 함께 본다. 도구 실패와 미완료 결과를 깨끗한 리뷰로 취급하지 않는다.

## 3. 반환 schema

```js
const REVIEW_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['reviewer', 'status', 'covered', 'findings', 'unverified'],
  properties: {
    reviewer: { type: 'string', maxLength: 80 },
    status: { type: 'string', enum: ['complete', 'incomplete'] },
    covered: { type: 'array', maxItems: 8, items: { type: 'string', maxLength: 180 } },
    findings: { type: 'array', maxItems: 5, items: {
      type: 'object', additionalProperties: false,
      required: ['severity', 'where', 'problem', 'fix'],
      properties: {
        severity: { type: 'string', enum: ['critical', 'concern', 'minor'] },
        where: { type: 'string', maxLength: 240 },
        problem: { type: 'string', maxLength: 400 },
        fix: { type: 'string', maxLength: 250 }
      }
    } },
    unverified: { type: 'array', maxItems: 8, items: { type: 'string', maxLength: 240 } }
  }
}
```

## 4. 도구 선택과 Workflow 골격

- 짧은 조사/검사는 메인이 직접 도구를 묶어 실행한다. 큰 독립 조사만 서브로 내린다.
- 읽기 전용은 Explore, 편집은 general-purpose다. 모델과 effort는 [model-routing.md](../notebook/common/model-routing.md)의 운영 표를 한 번 읽어 사용한다.
- Workflow가 있으면 effort 명시와 구조 반환에 사용한다. 없으면 Agent의 프롬프트에 반환 규격을 명시한다. Agent에 effort 필드가 없는 환경에서는 조절됐다고 주장하지 않는다.
- 플랜/명세 본문 대신 절대경로와 짧은 요약을 프롬프트 리터럴에 넣는다. 모델 호출에 필요한 입력을 불안정한 Workflow args에 의존하지 않는다.

```js
export const meta = {
  name: 'n-worker-review',
  description: '실제 변경의 위험 기반 리뷰',
  phases: [{ title: 'Review' }],
}
// §3의 REVIEW_SCHEMA 리터럴을 이 위치에 삽입한다.
phase('Review')
const lessonPaths = []  // 이번 작업과 관련된 노트북 lessons 절대경로 목록 (메인이 채운다 - 히트 0 이면 빈 배열). 경로는 nb-load 가 준 슬래시 표기 그대로.
const lessonNote = lessonPaths.length ? `먼저 읽고 대조할 검증된 기록(과거에 검증된 함정): ${lessonPaths.join(', ')}. ` : ''
const jobs = [
  { label: 'review:integration', model: 'sonnet', effort: 'medium',
    spec: '<$WORK>/review-integration.md' },
  // 고위험 작업에만 전문 리뷰 1개를 추가한다: { label: 'review:<표면>', model: 'opus', effort: 'high', spec: ... }
]
const out = await parallel(jobs.map(j => () => agent(
  `명세 ${j.spec} 를 먼저 읽고 맡긴 위험과 변경 지점만 확인하라. ` + lessonNote +
  `중요 지적 최대 5건. 추가 조사가 필요하면 확인한 결과와 미검증 범위를 반환하라. ` +
  `범위를 다 확인하지 못하면 incomplete와 unverified로 반환하라. 재위임하지 마라.`,
  { label: j.label, phase: 'Review', agentType: 'Explore',
    model: j.model, effort: j.effort, schema: REVIEW_SCHEMA }
)))
return {
  dead: jobs.filter((j, i) => !out[i]).map(j => j.label),
  reviews: out.map((r, i) => ({ reviewer: jobs[i].label,
    status: r ? r.status : 'failed', findings: r ? r.findings.length : null,
    unverified: r ? r.unverified.length : null }))
}
```

`parallel()`은 모든 작업 완료까지 반환하지 않는다. 서브 결과를 폴링하거나 전문을 `return`하지 않고 완료 알림의 journal 경로를 `scripts/wf-summarize.sh <journal>`로 읽는다. 요약에서 결과 누락, 실패, incomplete를 먼저 확인한다. 축약된 지적을 수정 근거로 삼아야 하면 해당 결과만 원문에서 확인한다.

`meta`는 순수 리터럴이다. Workflow 스크립트는 직접 파일/git에 접근하지 않고 agent가 수행한다. 골격 실행이 실패하면 1회만 고치고 Agent로 전환한다. 완료된 서브를 다시 실행하지 않는다. journal 파싱 실패 시 보존된 결과 파일을 확인하고, 복구할 수 없으면 미검증으로 남긴다.
