#!/bin/bash
# n-worker curator 데몬 - 세션과 독립된 프로세스. 큐를 순서대로 비운다.
# 단일 실행: lock/ 디렉터리(mkdir 원자성) + pid. 항목마다 새 `claude -p` 1회(컨텍스트 새로, 폭주 방지).
# 중지: curator-ctl.sh stop (항목 경계에서 종료). 모델 opus + effort high 는 model-routing §3 고정 배치.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
NB="$SKILL/notebook"; C="$NB/.curator"
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
  root="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['project_root'])" "$req")"
  mode="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mode'])" "$req")"
  effort="high"; case "$mode" in register|model-refresh) effort="medium";; esac
  done_file="$C/done/$id.json"; log="$C/logs/$id.log"
  prompt="너는 n-worker 스킬의 curator 다. 먼저 $SKILL/agents/curator.md 를 읽고 그 지침대로 행동하라 - 특히 '큐 실행 형태' 절. 스킬 경로: $SKILL. 요청 파일: $req (mode=$mode, 이 JSON 의 payload 가 네 입력이다). 끝나면 결과 JSON 을 $done_file 에 써라(형식은 curator.md '돌려줄 것' 의 큐 형식). 하위 서브는 최대 3개, 모델과 effort 는 $NB/common/model-routing.md §3 의 'curator 서브' 행을 읽어 정한다. 노트북($NB) 밖은 수정하지 않는다. 프로젝트 루트($root)는 읽기만 한다. 말하지 마라 - 서술,진행 보고,요약 출력 없이 도구 호출만 하고, 마지막 출력은 'done: $done_file' 한 줄이다."
  (cd "$NB" && claude -p "$prompt" \
      --name "curator-$id" --model opus --effort "$effort" \
      --permission-mode acceptEdits --add-dir "$NB" --add-dir "$root" \
      --allowedTools "Read" "Edit" "Write" "Grep" "Glob" "Agent" "Bash(python3 *)" "Bash(ls *)" "Bash(wc *)" "Bash(cat *)" "Bash(sed *)" "Bash(mv *)" "Bash(cp *)" "Bash(mkdir *)" "Bash(date *)" "Bash(git -C * log*)" "Bash(git -C * show*)" "Bash(git -C * rev-parse*)" "Bash(git -C * diff*)" \
      --max-turns 400 >"$log" 2>&1)
  rc=$?
  if [ ! -f "$done_file" ]; then
    python3 - "$done_file" "$id" "$rc" "$log" <<'PY'
import json,sys,datetime
p,id_,rc,log=sys.argv[1:5]
tail=open(log,encoding='utf-8',errors='replace').read()[-1500:] if __import__('os').path.exists(log) else ''
json.dump({"id":id_,"status":"failed","summary":f"curator 실행이 결과 파일을 남기지 않았다 (exit {rc}). 로그 꼬리:\n{tail}","finished_at":datetime.datetime.now(datetime.timezone.utc).isoformat()},open(p,"w",encoding='utf-8'),ensure_ascii=False,indent=1)
PY
  fi
  mv "$req" "$C/done/$id.request.json"; rm -f "$C/lock/current"
  echo "완료 $id (exit $rc)"
done
