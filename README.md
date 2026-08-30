<h1 align="center">n-worker</h1>
<h3 align="center">make Claude Code remember!</h3>
<p align="center"><b>세션이 끝나도 프로젝트를 기억하고, 코드를 쓰기 전에 스스로 계획을 깨보는<br>Claude Code 코드 작업 스킬</b><br>
매 세션 백지에서 시작하는 대신, 지난 세션이 배운 것 위에서 시작한다.</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT license"></a>
  <a href="https://claude.com/claude-code"><img src="https://img.shields.io/badge/Claude%20Code-Skill-d97757?logo=anthropic&logoColor=white" alt="Claude Code skill"></a>
  <img src="https://img.shields.io/badge/lang-%ED%95%9C%EA%B5%AD%EC%96%B4-blue" alt="Korean">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey" alt="platform">
</p>

```bash
git clone https://github.com/FuJiGraphics/n-worker.git ~/.claude/skills/n-worker
```

<table align="center">
  <tr>
    <td width="50%" align="center">
      <img src="docs/img/demo-interview.svg" alt="P1 인터뷰 - AskUserQuestion 으로 의도를 확정하고 plan.md 를 갱신하는 화면" width="410"><br>
      <sub><b>의도가 확정된 뒤에만 코드를 쓴다.</b><br>모호한 지점은 추천안과 함께 질문하고, 합의는 플랜 파일에 쌓인다.</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/img/demo-review.svg" alt="P2 사전 적대 리뷰 - 렌즈 5개가 플랜을 병렬로 깨보고 지적을 반영하는 화면" width="410"><br>
      <sub><b>코드를 쓰기 전에 깬다.</b><br>렌즈를 나눠 든 서브에이전트들이 플랜을 적대적으로 리뷰한다.</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="docs/img/demo-nbgrep.svg" alt="노트북 대조 - nb-grep 이 3층 인덱스에서 과거 함정을 찾아 본문을 동봉하는 화면" width="410"><br>
      <sub><b>같은 함정을 두 번 밟지 않는다.</b><br>파일을 손대기 전, 과거에 밟았던 함정을 자동으로 대조한다.</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/img/demo-record.svg" alt="P5 기록과 보고 - 검증 결과, 변경 요약 표, lesson 기록, pdf 보고서" width="410"><br>
      <sub><b>다음 세션이 이어받는다.</b><br>배운 것은 노트북에 기록되고, 보고서까지 남기고 끝난다.</sub>
    </td>
  </tr>
</table>

n-worker 는 무거운 코드 작업(기능 추가, 리팩토링, 설계가 필요한 버그수정)을 위한 대화형 파이프라인이다.
인터뷰로 의도를 확정하고, 살아있는 플랜 파일을 사용자와 함께 키우고, 생산 전에 적대 리뷰로 계획을 깨보고,
생산-검증-지식 기록까지 완주한다. 그리고 그 과정에서 배운 것을 **3층 노트북**에 남겨,
다음 세션의 Claude 가 프로젝트의 구조, 컨벤션, 함정을 이미 아는 상태로 시작하게 한다.

## 왜 필요한가

Claude Code 로 무거운 작업을 하다 보면 반복되는 문제가 있다:

| 문제 | n-worker 의 해결 |
|---|---|
| 매 세션이 백지에서 시작한다 - 프로젝트 설명을 반복하거나, 빼먹고 사고가 난다 | **3층 노트북** - 확인된 사실만 누적하고 다음 세션이 자동 로드 |
| 모호한 요청을 임의로 해석해서 만든 결과물은 재작업이 된다 | **인터뷰** - 추천안과 함께 질문하고 플랜 파일로 합의를 고정 |
| 구조 위반, 중복 구현, 놓친 회귀는 코드가 쌓인 뒤 발견되면 비싸다 | **사전 적대 리뷰** - 코드를 쓰기 전에 렌즈 리뷰로 깬다 |
| 긴 세션은 같은 내용이 매 턴 재전송되며 비용이 샌다 | **컨텍스트 경제** - 인덱스 점진 로딩, 서브 위임, 출력 리다이렉트 |

## 빠른 시작

```bash
git clone https://github.com/FuJiGraphics/n-worker.git ~/.claude/skills/n-worker
```

Claude Code 세션에서 프로젝트 폴더를 열고:

```
/n-worker 인벤토리에 아이템 잠금 기능 추가해줘
```

첫 발동 시 프로젝트 등록 질문(슬러그, 스택, 컨벤션 문서 위치)에 답하면 노트북 골격이 만들어지고,
이후 세션부터는 자동으로 로드된다.

> [!NOTE]
> 단순 질문이나 한 줄 수정에는 쓰지 않는다. 이 스킬은 "의도 확정과 검증에 왕복을 쓸 가치가 있는"
> 무거운 작업 전용이다.

## 동작 방식 - 6단계 파이프라인

<p align="center">
  <img src="docs/img/pipeline.svg" alt="P0 컨텍스트 → P1 인터뷰 → P2 사전 리뷰 → P3 생산 → P4 검증 → P5 기록/보고. P1~P2 는 편집 잠금, P5 의 기록을 다음 세션 P0 가 이어받는다" width="900">
</p>

| 단계 | 하는 일 |
|---|---|
| **P0 컨텍스트** | 노트북 로드, 프로젝트 식별, 작업 무게 확인 |
| **P1 인터뷰** | 질문 ↔ 답 ↔ 플랜 갱신 ↔ 병렬 조사 - 의도가 수렴할 때까지 |
| **P2 사전 리뷰** | 난이도 판정 → 적대 리뷰(렌즈) → 취합 → 플랜 승인 |
| **P3 생산** | 복제 후 적응 - 기존 구현을 본떠 차이만 바꾼다. 대형 묶음은 서브에 위임 |
| **P4 검증** | 자동 검증 반복 - 로그는 발췌로만, 의도대로 동작할 때까지 |
| **P5 기록과 보고** | 배운 것을 노트북에 기록 → 변경 요약 표 → (선택) pdf/html 보고서 |

핵심 설계 결정:

- **P1~P2 편집 잠금.** 플랜이 승인되기 전에는 프로젝트 파일을 읽기만 한다. 코드가 먼저 쌓이는 사고를 구조적으로 막는다.
- **리뷰는 생산 전에 한 번뿐.** 생산 후 정적 리뷰가 없는 대신, 리뷰 입력이 "쓸 코드"가 되도록 파일별 변경 계획과 코드 초안을 플랜에 먼저 적는다.
- **복제 후 적응이 생성보다 우선.** 처음부터 새로 짜지 않고 그 프로젝트에서 가장 가까운 기존 구현을 본뜬다. 컨벤션은 저절로 따라온다.
- **읽은 것만 진실.** 노트북도 "과거에 검증된 기록"일 뿐, 동작을 걸기 전에는 라이브 코드로 다시 확인한다.

## 3층 노트북 - 장기기억의 구조

<p align="center">
  <img src="docs/img/notebook.svg" alt="projects, stacks, common 3층 구조. nb-load 와 nb-grep 이 읽고, curator 서브에이전트만 쓴다" width="900">
</p>

- 층은 "이 사실이 어디까지 일반화되는가"로 가른다. 프로젝트 고유 사실은 `projects/`, 엔진/프레임워크 일반은 `stacks/`, 스택 무관 함정은 `common/`.
- **쓰기 창구는 하나다.** 기록, 승격/강등, 정비는 전담 서브에이전트(curator)만 한다 - 창구가 하나여야 규율이 갈라지지 않는다.
- **기록 게이트.** 조사 비용을 치르고 알아낸 것, 사용자가 말해줘야만 알 수 있는 것만 기록한다. 코드를 열면 몇 초에 확인되는 것은 기록하지 않는다.
- **전량 로드는 없다.** 얇은 인덱스만 읽고 본문은 이번 작업에 걸릴 때만 펼친다.
- 노트북은 설치한 기기에서 자란다. `.gitignore` 가 누적 지식을 추적에서 빼므로 개인 프로젝트 정보가 레포에 섞이지 않는다.

## 선택 설정 - 노트북 게이트 (PreToolUse 훅)

"파일을 고치기 전에 노트북을 대조한다"를 스킬 지시가 아니라 하네스 수준에서 강제할 수 있다.
`~/.claude/settings.json` 에:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$HOME/.claude/skills/n-worker/scripts/nb-gate.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- `scripts/nb-gate.mode` 가 `shadow` 면 기록만 하고 막지 않는다(기본값). `block` 으로 바꾸면 대조 기록 없는 프로젝트 파일 수정이 거부된다.
- 훅 없이도 스킬은 동작한다 - 게이트는 규율의 보험이다.

## 폴더 구조

```
n-worker/
├── SKILL.md               # 진입점 - 파이프라인 본문과 준칙
├── references/            # 단계별 상세 절차 (점진 로드)
│   ├── interview.md       #   P1 인터뷰, 질문 설계, 수렴 판정
│   ├── plan.md            #   플랜 파일 포맷
│   ├── review.md          #   P2 난이도 판정, 렌즈 카탈로그
│   ├── produce.md         #   P3 복제 후 적응, 위임 명세
│   ├── verify.md          #   P4 검증, 로그 판독, 핸드오프
│   └── report-render.md   #   html/pdf 보고서 규격
├── agents/
│   ├── curator.md         # 노트북 쓰기 전담 서브 (등록/기록/정비)
│   └── reporter.md        # 결과 보고서 생성 서브
├── scripts/
│   ├── nb-load.sh         # P0 노트북 로더 (registry + 3층 인덱스 1방 로딩)
│   ├── nb-grep.sh         # 함정 대조 (3층 인덱스 grep + 히트 본문 동봉 + 로그)
│   ├── nb-gate.sh         # PreToolUse 게이트 (선택)
│   └── open-artifact.sh   # 산출물 열기 (md 를 에디터로)
├── notebook/              # 장기기억 (시드 골격 - 설치 후 여기서 자란다)
└── assets/                # html 보고서 템플릿
```

## 요구사항

| 항목 | 내용 |
|---|---|
| [Claude Code](https://claude.com/claude-code) | 스킬, 서브에이전트, `AskUserQuestion` 지원 버전 |
| 셸 | bash (macOS / Linux 검증) |
| 언어 | 스킬 본문과 진행 대화가 한국어다. 영어 환경에서도 동작은 하지만 질문과 플랜이 한국어로 나온다 |

## License

[MIT](LICENSE) - 수정과 재배포는 자유이며, 저작권 표시를 유지해 주세요.
