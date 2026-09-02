# harness-routing - 이 스킬이 기댄 하네스(Claude Code) 동작 목록

> 스킬은 프롬프트, 훅, `claude -p`, Workflow 같은 하네스 표면 위에서 돈다. 그중 문서에 없는 관측 동작에 기댄 곳을 여기 모은다. model-routing.md 가 모델 세대 노후화를 잡는 것과 같은 원리로 이 파일은 하네스 버전 노후화를 잡는다. 층은 common(어느 스택, 프로젝트에서도 같은 사실).

```
checked: 2026-09-03
checked_version: claude-code_2-1-258_agent
갱신 트리거 (하나라도 걸리면 curator harness-refresh 를 큐에 넣는다):
  ① nb-load 가 읽은 현재 버전(env AI_AGENT, 없으면 `claude --version`)이 checked_version 과 다르다 - nb-load 가 한 줄 알린다
  ② 아래 표의 항목이 실행 중 깨졌다(데몬 done 파일 denied, wf-summarize 0건 파싱, 게이트 미발화)
  ③ checked 가 60일 이상 지났다
  ④ 사용자가 갱신을 요청했다
```

## 1. 원칙

- 관측한 하네스 동작을 스킬 규칙으로 승격할 때는 여기에 행을 만든다. 문서화된 동작은 근거 칸에 `문서`, 관측만 된 동작은 `관측 <날짜>` 로 적는다.
- 행마다 "깨졌을 때" 가 있어야 한다. 폴백 없는 의존은 만들지 않는다.
- 확인하지 못한 것은 "미확인" 으로 둔다. 추측을 적으면 이후 전 세션의 동작이 오염된다.

## 2. 항목

| # | 가정 | 사용 위치 | 근거 | 깨졌을 때 |
|---|---|---|---|---|
| 1 | `.claude/` 는 protected path - Edit/Write 마다 대화형 승인 강제. acceptEdits, allow 규칙(`Edit(경로/**)`), 훅 `permissionDecision: allow` 어느 것으로도 못 넘는다. 건너뛰는 유일한 수단은 bypassPermissions. deny 규칙은 bypass 에서도 유효. 운영체제 무관 | scripts/curator-daemon.sh(권한 플래그, `--tools`, `--disallowedTools`) | 문서 permission-modes.md, permissions.md + 관측 2026-09-03(acceptEdits, allow, 훅 전부 `which is a sensitive file` 로 거부) | 데몬 done 파일 `status: denied` → nb-load 가 알린다. 대안은 노트북을 `~/.claude` 밖으로 옮기는 것 |
| 2 | Bash 도구 환경변수에 `CLAUDE_CODE_SESSION_ID`(훅 stdin `session_id` 와 같은 값), `CLAUDE_EFFORT`, `AI_AGENT`(`claude-code_<버전>_agent`) 가 있다 | scripts/nb-load.sh(마커 sid, 버전 비교), scripts/nb-gate.sh(세션 귀속) | 관측 2026-09-03, 미문서 | 게이트가 세션을 못 찾아 전부 통과(fail-open). nb-load 가 "세션 id 환경변수 없음" 을 알린다 |
| 3 | PreToolUse 훅 stdin JSON 에 `session_id`, `tool_input.file_path`. exit 2 = 차단 + stderr 를 모델에 피드백 | scripts/nb-gate.sh | 문서 hooks-guide.md | - |
| 4 | Workflow `return` 값은 완료 알림으로 메인 컨텍스트에 통째 주입되고 약 24KB 에서 잘린다 | SKILL.md 컨텍스트 경제 절, references/review.md §4 함정 4 | 관측 2026-08(51KB 결과에서 27KB 도착), 미문서 | 건수만 return 하므로 잘림 자체는 무해. journal 판독(#6)이 깨지면 return 전문으로 폴백 |
| 5 | Workflow `args` 는 문자열화되거나 유실될 수 있다 | references/review.md §4 함정 1 | 관측 2026-07, 미문서 | 이미 프롬프트 리터럴(경로 + 요약)로 우회. 폴백 불필요 |
| 6 | Workflow 가 journal.jsonl 을 남기고 완료 알림 diagnostics 에 경로가 온다. 한 줄 = `{type:"result", key, result}` | scripts/wf-summarize.py, references/review.md §4 | 관측 2026-08, 미문서 | wf-summarize 가 0건 파싱이면 exit 1 → 서브 return 전문으로 폴백(24KB 한도 감수) |
| 7 | Workflow 스크립트: `parallel()` 은 throw 항목을 null 로, `meta` 는 순수 리터럴만, `Date.now()` 류는 throw | references/review.md §4 | 관측 2026-07~08 + 도구 설명 | 같은 스크립트 2회 실패 시 raw Agent 폴백(review.md §4) |
| 8 | `Agent` 도구 스키마에 `effort` 파라미터가 없다(`model` 은 있다). effort 차등은 Workflow `agent()` 에서만 가능 | SKILL.md 서브에이전트 운용 절 | 관측 2026-09-03(세션 도구 정의) | Agent 스폰은 세션 effort 상속으로 동작. 규칙은 Workflow 한정 |
| 9 | `AskUserQuestion` 문항 상한 4 | references/interview.md | 문서(도구 스키마) | - |
| 10 | 서브 `model` 별칭 `'opus'`, `'sonnet'` 유효 | model-routing.md | 관측 2026-09-02 | model-routing 트리거 ③ |
| 11 | `claude -p` 플래그 `--tools "A,B"`, `--disallowedTools`, `--strict-mcp-config`, `--add-dir`, `--max-turns`, `--effort`, `--name` | scripts/curator-daemon.sh | 문서 cli-reference + `claude -p --help` 2026-09-03 | 데몬 로그에 플래그 오류 → done `failed` |
| 12 | 헤드리스 `claude -p` 안에서 `Agent` 로 띄운 하위 서브가 상위의 권한, 도구 제한을 물려받는지 | 사용 안 함 - curator 는 하위 서브를 쓰지 않는다(사용자 결정 2026-09-03) | 미문서. 관측 2026-09-03: acceptEdits 상위에서 서브의 Write/Edit/Bash 전부 거부 | 해당 없음 |

## 3. [깨짐] 기록

- 없음 (2026-09-03)

## 4. 미검증 (Windows)

- **cygpath 경로 변환**(`scripts/curator-daemon.sh` 의 `native()`)은 2026-09-03 에 검증 없이 넣었다. 하네스가 Git Bash 에서 `C:\...` 표기를 원한다는 전제이고, POSIX 표기(`/c/Users/...`)를 원한다면 이 변환이 오히려 경로를 깨뜨린다. **윈도우에서 데몬이 경로 오류를 내면 그 함수 호출을 지우고 원래 변수를 그대로 쓰면 된다**(그 상태가 2026-09-03 패치 이전과 같다). macOS/Linux 에는 `cygpath` 가 없어 무영향.
- 같은 이유로 미검증: Git Bash 에서 `nohup`, `disown` 이 데몬을 터미널에서 떼어내는지(죽어도 큐는 남고 다음 enqueue 가 다시 띄운다), `~/.claude` protected path 규칙이 윈도우에서도 같은지.

## 5. 실측 기록 (2026-09-03, macOS, 2.1.258)

- 헤드리스 `claude -p --permission-mode acceptEdits` 로 `~/.claude` 아래 쓰기: `Edit`/`Write` 는 거부, `Bash` 는 통과. 즉 protected path 검사는 파일 편집 도구에만 걸린다.
- 데몬 실제 실행(harness-refresh 1건): 큐 투입, 잠금, 항목 이동, opus 실행, 종료까지 정상. 쓰기 단계에서 거부돼 done 파일과 `.pending.md` 를 남기지 못했다. **`scripts/curator-perm.mode` 가 없으면 데몬은 판정만 하고 기록을 못 한다.**
- 그 실행에서 데몬의 거부 판정이 `failed` 로 잘못 찍혔다 - 모델이 "쓰기 권한 문제" 로 요약해 `requested permissions` 문자열이 로그에 없었다. 판정 패턴을 두 갈래(하네스 메시지와 모델 서술)로 넓혔다.

verified: 2026-09-03 (Claude Code 2.1.258, 이 환경의 실측 + 공식 문서)
