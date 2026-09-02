#!/bin/bash
# n-worker curator 데몬 - 세션과 독립된 프로세스. 큐를 순서대로 비운다.
# 단일 실행: lock/ 디렉터리(mkdir 원자성) + pid. 항목마다 새 `claude -p` 1회(컨텍스트 새로, 폭주 방지).
# 중지: curator-ctl.sh stop (항목 경계에서 종료). 모델 opus + effort high 는 model-routing §3 고정 배치.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
NB="$SKILL/notebook"; C="$NB/.curator"
PY="$(command -v python3 || command -v python)"   # Windows(Git Bash)에는 python3 이름이 없을 수 있다
# 권한 모드는 scripts/curator-perm.mode 파일(한 단어)이 정한다. 근거와 배포 기본값은 notebook/common/harness-routing.md #1 과 README.
# 파일이 없으면 acceptEdits - 그 경우 `~/.claude` 아래 노트북 쓰기는 하네스가 거부하고 done 파일이 denied 로 남는다.
PERM_MODE="$(cat "$SKILL/scripts/curator-perm.mode" 2>/dev/null | tr -d ' \r\n')"
[ -n "$PERM_MODE" ] || PERM_MODE="acceptEdits"
# Windows(Git Bash)에서는 bash 표기 경로(/c/Users/...)를 하네스 도구가 못 읽을 수 있다. cygpath 가 있으면 네이티브 표기로 바꿔
# 프롬프트와 플래그에 넘긴다. macOS/Linux 에는 cygpath 가 없어 경로가 그대로 나온다.
native() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }
skill_n="$(native "$SKILL")"; nb_n="$(native "$NB")"; cur_n="$(native "$SKILL/agents/curator.md")"
IDLE_ROUNDS=2; IDLE_SLEEP=30
mkdir -p "$C/queue" "$C/processing" "$C/done" "$C/logs"
# 잠금 - 죽은 pid 면 넘겨받는다
if ! mkdir "$C/lock" 2>/dev/null; then
  if [ -f "$C/lock/pid" ] && kill -0 "$(cat "$C/lock/pid")" 2>/dev/null; then echo "이미 실행 중 (pid $(cat "$C/lock/pid"))"; exit 0; fi
  rm -rf "$C/lock"; mkdir "$C/lock" || exit 1
fi
echo $$ > "$C/lock/pid"; date -u +%Y-%m-%dT%H:%M:%SZ > "$C/lock/started"; rm -f "$C/stop"
cleanup() { rm -rf "$C/lock"; }
trap cleanup EXIT
idle=0
while :; do
  if [ -f "$C/stop" ]; then echo "중지 요청 - 종료"; rm -f "$C/stop"; break; fi
  next="$(ls "$C/queue"/*.json 2>/dev/null | head -1)"
  if [ -z "$next" ]; then
    idle=$((idle+1)); [ "$idle" -ge "$IDLE_ROUNDS" ] && { echo "큐 비어 있음 - 종료"; break; }
    sleep "$IDLE_SLEEP"; continue
  fi
  idle=0
  id="$(basename "$next" .json)"; req="$C/processing/$id.json"; mv "$next" "$req"
  echo "$id" > "$C/lock/current"; date -u +%Y-%m-%dT%H:%M:%SZ > "$C/lock/heartbeat"
  root="$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf-8'))['project_root'])" "$req")"
  mode="$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf-8'))['mode'])" "$req")"
  effort="high"; case "$mode" in register|model-refresh|harness-refresh) effort="medium";; esac
  done_file="$C/done/$id.json"; log="$C/logs/$id.log"
  req_n="$(native "$req")"; done_n="$(native "$done_file")"; root_n="$(native "$root")"
  prompt="너는 n-worker 스킬의 curator 다. 먼저 $cur_n 를 읽고 그 지침대로 행동하라 - 특히 '큐 실행 형태' 절. 스킬 경로: $skill_n. 노트북 경로: $nb_n. 요청 파일: $req_n (mode=$mode, 이 JSON 의 payload 가 네 입력이다). 끝나면 결과 JSON 을 $done_n 에 써라(형식은 curator.md '돌려줄 것' 의 큐 형식). 하위 서브에이전트는 쓰지 않는다 - 전부 직접 한다. 노트북($nb_n) 밖은 수정하지 않는다. 프로젝트 루트($root_n)는 읽기만 한다. git 으로 커밋, 푸시, 체크아웃, 리셋을 하지 않는다. 말하지 마라 - 서술,진행 보고,요약 출력 없이 도구 호출만 하고, 마지막 출력은 'done: $done_n' 한 줄이다."
  (cd "$NB" && claude -p "$prompt" \
      --name "curator-$id" --model opus --effort "$effort" \
      --permission-mode "$PERM_MODE" \
      --tools "Read,Edit,Write,Grep,Glob,Bash" \
      --allowedTools "Read" "Edit" "Write" "Grep" "Glob" "Bash(python3 *)" "Bash(python *)" "Bash(ls *)" "Bash(wc *)" "Bash(cat *)" "Bash(sed *)" "Bash(mv *)" "Bash(cp *)" "Bash(mkdir *)" "Bash(date *)" "Bash(git -C * log*)" "Bash(git -C * show*)" "Bash(git -C * rev-parse*)" "Bash(git -C * diff*)" \
      --disallowedTools "Bash(git push*)" "Bash(git commit*)" "Bash(git reset*)" "Bash(git checkout*)" "Bash(git switch*)" "Bash(git stash*)" "Bash(git rebase*)" "Bash(git merge*)" "Bash(rm *)" "Bash(sudo *)" \
      --strict-mcp-config \
      --add-dir "$root_n" \
      --max-turns 400 >"$log" 2>&1)
  rc=$?
  if [ ! -f "$done_file" ]; then
    # denied = 하네스가 도구 호출을 권한으로 거부한 흔적이 있다(harness-routing.md #1 재검증 신호). 그 외는 failed.
    status="failed"
    # 거부 문구는 하네스 메시지와 모델 서술 두 갈래로 온다(실측 2026-09-03: 모델이 "쓰기 권한 문제"로 요약해
    # "requested permissions" 만 찾으면 failed 로 잘못 찍혔다). 둘 다 본다.
    grep -qiE "requested permissions|sensitive file|permission denied|쓰기 권한|권한 거부|권한 문제" "$log" 2>/dev/null && status="denied"
    "$PY" - "$done_file" "$id" "$rc" "$log" "$status" <<'PY'
import json,sys,datetime,os
p,id_,rc,log,status=sys.argv[1:6]
tail=open(log,encoding='utf-8',errors='replace').read()[-1500:] if os.path.exists(log) else ''
json.dump({"id":id_,"status":status,"summary":f"curator 실행이 결과 파일을 남기지 않았다 (exit {rc}, 판정 {status}). 로그 꼬리:\n{tail}","finished_at":datetime.datetime.now(datetime.timezone.utc).isoformat()},open(p,"w",encoding='utf-8'),ensure_ascii=False,indent=1)
PY
  fi
  mv "$req" "$C/done/$id.request.json"; rm -f "$C/lock/current"
  echo "완료 $id (exit $rc)"
done
