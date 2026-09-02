#!/usr/bin/env python3
"""n-worker: Workflow journal.jsonl 압축 판독기.
스크립트가 return 으로 전문을 돌려주면 완료 알림이 그 전문을 메인 컨텍스트에 밀어 넣고(24KB 에서 잘려 꼬리 유실),
메인이 다시 압축본을 만들어 읽어 두 번 든다. 그래서 Workflow 는 건수만 return 하고 전문은 이 스크립트로 읽는다.
사용법: wf-summarize.py <journal.jsonl> [--problem N] [--fix N] [--full critical,behavior] [--json-out <경로>]
결과 shape 를 보고 모드를 고른다: findings(리뷰/동일성) / members(조사) / status+created(생산) / 그 밖은 키 요약.
critical(behavior) 은 전문, 나머지는 축약. 원문은 journal 에 그대로 남는다."""
import json, sys, html, argparse
ap = argparse.ArgumentParser()
ap.add_argument("journal"); ap.add_argument("--problem", type=int, default=240); ap.add_argument("--fix", type=int, default=160)
ap.add_argument("--full", default="critical,behavior"); ap.add_argument("--json-out", default=None)
a = ap.parse_args()
full = set(a.full.split(","))
res = []
for line in open(a.journal, encoding="utf-8"):
    try: d = json.loads(line)
    except Exception: continue
    if d.get("type") == "result" and isinstance(d.get("result"), dict):
        res.append((d.get("key", ""), d["result"]))
if a.json_out:
    json.dump([r for _, r in res], open(a.json_out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
u = html.unescape
def cut(s, n): s = u(str(s)).replace("\n", " "); return s if len(s) <= n else s[:n] + "…"
rank = {"critical": 0, "behavior": 0, "visual": 1, "concern": 1, "timing": 2, "minor": 3, "none": 3}
print(f"에이전트 {len(res)}개 (journal: {a.journal})")
if not res: sys.exit(0)
shape = res[0][1]
if "findings" in shape:
    allf = [dict(f, _agent=k[:24]) for k, r in res for f in r.get("findings", [])]
    counts = {}
    for f in allf: counts[f.get("severity", "?")] = counts.get(f.get("severity", "?"), 0) + 1
    clean = [k[:24] for k, r in res if r.get("cleanWithinLens", r.get("clean")) and not r.get("findings")]
    print(f"findings {len(allf)} {counts} / 깨끗한 렌즈 {clean}")
    allf.sort(key=lambda f: rank.get(f.get("severity", ""), 9))
    for i, f in enumerate(allf, 1):
        sev = f.get("severity", "?"); big = sev in full
        where = f.get("where") or f"{f.get('file','')} :: {f.get('member','')}"
        print(f"\n[{i}] {sev.upper()} ({f.get('lens', f['_agent'])[:14]}) @ {cut(where, 110)}")
        if "problem" in f:
            print("  문제:", u(f["problem"]) if big else cut(f["problem"], a.problem))
        else:
            print("  전:", u(f.get("before", "")) if big else cut(f.get("before", ""), a.problem))
            print("  후:", u(f.get("after", "")) if big else cut(f.get("after", ""), a.problem))
        print("  수정:", u(f.get("fix", "")) if big else cut(f.get("fix", ""), a.fix))
elif "members" in shape:
    print("| 파일 | 줄 | 베이스 | ctrl/both/view | 로직 요약 |\n|---|---|---|---|---|")
    for _, r in sorted(res, key=lambda x: x[1].get("file", "")):
        ms = r["members"]; c = sum(m.get("target") == "controller" for m in ms); b = sum(m.get("target") == "both" for m in ms); v = len(ms) - c - b
        print(f"| {r.get('file','').split('/')[-1]} | {r.get('lines','?')} | {cut(r.get('baseType',''),20)} | {c}/{b}/{v} | {cut(r.get('logicSummary',''),100).replace('|','/')} |")
elif "status" in shape and "created" in shape:
    for _, r in res:
        print(f"\n## {r.get('batch', r.get('id',''))} status={r['status']} created={len(r.get('created',[]))} modified={len(r.get('modified',[]))} mismatch={cut(r.get('mismatch','') or '없음', 200)}")
        print("  생성:", ", ".join(p.split("/")[-1] for p in r.get("created", [])))
        print("  수정:", ", ".join(p.split("/")[-1] for p in r.get("modified", [])))
        for q in r.get("questions", []): print("  Q:", cut(q, 300))
else:
    for k, r in res:
        print(f"\n## {k[:24]}")
        for kk, vv in r.items():
            s = json.dumps(vv, ensure_ascii=False); print(f"  {kk}: {cut(s, 200)}")
