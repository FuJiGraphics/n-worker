#!/bin/bash
# n-worker curator 큐 투입. 어느 세션이든 이 한 줄로 curator 에 일을 맡긴다.
# 사용법: curator-enqueue.sh <요청 JSON 경로> [--wait <초>]
#   요청 JSON 필수 키: mode(register|record|targeted|sweep|model-refresh), project_root, slug, stack,
#                     caller(호출 세션 이름), payload(모드별 입력 - record 면 proposals[], scripts[] 등)
#   --wait 를 주면 done 파일이 생길 때까지 폴링해 요약을 출력한다(register 처럼 결과가 즉시 필요한 모드용).
# 동작: queue/ 에 <ISO시각>-<caller>.json 으로 넣고, 살아 있는 데몬이 없으면 curator-daemon.sh 를 detach 로 띄운다.
#       살아 있으면 큐만 쌓고 반환한다 - 데몬은 큐를 순서대로 비운다(단일 실행, 단일 쓰기 주체).
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
C="$SKILL/notebook/.curator"
REQ="${1:-}"; WAIT=0
[ -n "$REQ" ] && [ -f "$REQ" ] || { echo "오류: 요청 JSON 경로가 필요하다"; exit 2; }
if [ "${2:-}" = "--wait" ]; then WAIT="${3:-600}"; fi
mkdir -p "$C/queue" "$C/processing" "$C/done" "$C/logs"
python3 - "$REQ" <<'PY' || exit 2
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
for k in ("mode","project_root","slug","caller","payload"):
    if k not in d: print(f"오류: 요청 JSON 에 '{k}' 가 없다"); sys.exit(1)
if d["mode"] not in ("register","record","targeted","sweep","model-refresh"): print("오류: mode 값이 아니다"); sys.exit(1)
PY
TS="$(date -u +%Y%m%dT%H%M%SZ)"
CALLER="$(python3 -c "import json,sys,re; print(re.sub(r'[^A-Za-z0-9_-]','_',json.load(open(sys.argv[1]))['caller'])[:40])" "$REQ")"
ID="${TS}-${CALLER}-$$"
python3 - "$REQ" "$C/queue/$ID.json" "$ID" <<'PY'
import json,sys,datetime
d=json.load(open(sys.argv[1],encoding='utf-8')); d["id"]=sys.argv[3]; d["enqueued_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
tmp=sys.argv[2]+".tmp"; json.dump(d,open(tmp,"w",encoding='utf-8'),ensure_ascii=False,indent=1)
import os; os.replace(tmp,sys.argv[2])
PY
echo "큐 투입: $ID"
# 데몬 생존 확인 - lock/pid 의 프로세스가 살아 있으면 큐만 쌓는다
if [ -f "$C/lock/pid" ] && kill -0 "$(cat "$C/lock/pid" 2>/dev/null)" 2>/dev/null; then
  echo "데몬 실행 중 (pid $(cat "$C/lock/pid"), 현재: $(cat "$C/lock/current" 2>/dev/null || echo '-')) - 큐에 쌓아 두었다"
else
  nohup bash "$SKILL/scripts/curator-daemon.sh" >"$C/logs/daemon.out" 2>&1 &
  disown 2>/dev/null || true
  echo "데몬 기동 (pid $!) - 로그 $C/logs/daemon.out"
fi
if [ "$WAIT" -gt 0 ]; then
  for i in $(seq 1 "$WAIT"); do
    if [ -f "$C/done/$ID.json" ]; then python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('status','?')); print(d.get('summary',''))" "$C/done/$ID.json"; exit 0; fi
    sleep 1
  done
  echo "대기 ${WAIT}초 초과 - 나중에 curator-ctl.sh status 로 확인"; exit 3
fi
