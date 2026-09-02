#!/bin/bash
# n-worker curator 데몬 제어. 어느 세션에서든 쓴다.
# 사용법: curator-ctl.sh status | stop | kill | results [--ack] | log [id]
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"; C="$SKILL/notebook/.curator"
PY="$(command -v python3 || command -v python)"   # Windows(Git Bash)에는 python3 이름이 없을 수 있다
cmd="${1:-status}"
alive() { [ -f "$C/lock/pid" ] && kill -0 "$(cat "$C/lock/pid" 2>/dev/null)" 2>/dev/null; }
case "$cmd" in
  status)
    if alive; then echo "데몬: 실행 중 pid $(cat "$C/lock/pid") (시작 $(cat "$C/lock/started" 2>/dev/null), 현재 항목: $(cat "$C/lock/current" 2>/dev/null || echo '대기'), 심장박동 $(cat "$C/lock/heartbeat" 2>/dev/null || echo '-'))"; else echo "데몬: 없음$( [ -d "$C/lock" ] && echo ' (죽은 잠금 - 다음 enqueue 가 넘겨받는다)')"; fi
    echo "큐 대기: $(ls "$C/queue"/*.json 2>/dev/null | wc -l | tr -d ' ')건 / 처리 중: $(ls "$C/processing"/*.json 2>/dev/null | wc -l | tr -d ' ')건 / 완료: $(ls "$C/done"/*.json 2>/dev/null | grep -vc request.json)건"
    ls "$C/queue"/*.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/^/  대기: /';;
  stop) touch "$C/stop"; echo "중지 요청 - 현재 항목이 끝나면 종료된다";;
  kill) alive && kill "$(cat "$C/lock/pid")" && rm -rf "$C/lock" && echo "강제 종료" || echo "실행 중인 데몬 없음";;
  results)
    "$PY" - "$C/done" "${2:-}" <<'PY'
import json,sys,glob,os
d,ack=sys.argv[1],sys.argv[2]=="--ack"
for p in sorted(glob.glob(os.path.join(d,"*.json"))):
    if p.endswith(".request.json"): continue
    r=json.load(open(p,encoding='utf-8'))
    if r.get("seen") and not ack: continue
    print(f"--- {r.get('id')} [{r.get('status')}] {r.get('finished_at','')}\n{r.get('summary','')}\n")
    if ack and not r.get("seen"):
        r["seen"]=True; json.dump(r,open(p,"w",encoding='utf-8'),ensure_ascii=False,indent=1)
PY
    ;;
  log) id="${2:-}"; [ -n "$id" ] && tail -40 "$C/logs/$id.log" || tail -20 "$C/logs/daemon.out" 2>/dev/null;;
  *) echo "사용법: curator-ctl.sh status | stop | kill | results [--ack] | log [id]";;
esac
