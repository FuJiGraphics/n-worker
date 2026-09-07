#!/usr/bin/env python3
"""nb-gate.sh 의 Bash 매처 보조 - 훅 입력(stdin JSON)의 Bash 명령문에서 프로젝트 파일 쓰기 대상을 뽑아 한 줄에 하나씩 출력한다.

왜 별도 파일인가: bash 는 `$( ... <<'PY' ... PY )` 안의 python 소스에 든 ')' 를 command substitution 의 닫는 괄호로
오인해 런타임 구문 오류를 낸다(notebook/common/lessons/deferred-parse-defeats-syntax-check.md). 그래서 스크립트 파일로 둔다.

휴리스틱 범위(전부 fail-open - 못 뽑으면 대상 없음으로 통과한다):
- 리다이렉션 `>`, `>>` 의 대상 (2>&1, >&2, <<, -> 제외)
- cp / mv 의 목적지 (목적지가 폴더면 원본 basename 을 붙인 경로)
- sed -i 의 파일 인자, tee 의 파일 인자, rm 의 인자
- `unity command eval_file --file X` 면 X 안의 "Assets/..." 문자열 리터럴, 그 외 에셋 쓰기 커맨드의 Assets/ 인자
- 쓰기 신호(open(..., "w"), .write(, write_text 등)가 있는 인라인 스크립트의 경로 리터럴
미확장 셸 변수($X/...)는 판정할 수 없어 버린다. 상대경로는 훅의 cwd → 프로젝트 루트 순으로 해석한다.
존재하지 않고 상위 폴더도 없는 토큰은 경로가 아닌 것으로 본다.

사용법: nb-gate-bash.py <프로젝트 루트>  (stdin = 훅 JSON)
"""
import json
import os
import re
import shlex
import sys

root = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
cmd = ti.get("command") or ""
cwd = d.get("cwd") or root
if not cmd or not root:
    sys.exit(0)

targets = []


def add(p, must_exist=False):
    p = (p or "").strip().strip("\"'")
    if not p or p.startswith("-") or p.startswith("&") or p.startswith("$") or p == "/dev/null":
        return
    if "/" not in p and "." not in p:
        return  # 경로로 보기 어려운 낱말(비교 연산자 뒤의 토큰 등)
    targets.append((p, must_exist))


# 1) 리다이렉션
for m in re.finditer(r'(?<![<>&\d-])>{1,2}\s*(?:"([^"]+)"|\'([^\']+)\'|([^\s;|&<>()]+))', cmd):
    add(m.group(1) or m.group(2) or m.group(3))

# 2) 단순 명령 단위
UNITY_WRITE = {"eval_file", "set_serialized_field", "create_asset", "create_prefab",
               "apply_prefab_overrides", "add_component", "set_import_settings"}
ASSET_RE = r"(?:Assets|Packages|ProjectSettings)/"
for seg in re.split(r"(?:&&|\|\||[;|\n])", cmd):
    seg = seg.strip()
    if not seg:
        continue
    try:
        argv = shlex.split(seg, posix=True)
    except ValueError:
        argv = seg.split()
    i = 0
    while i < len(argv) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", argv[i]):
        i += 1
    argv = argv[i:]
    if not argv:
        continue
    c = os.path.basename(argv[0])
    args = [a for a in argv[1:] if not a.startswith("-")]
    if c in ("cp", "mv") and len(args) >= 2:
        dest, srcs = args[-1], args[:-1]
        dabs = dest if os.path.isabs(dest) else os.path.join(cwd, dest)
        if dest.endswith("/") or os.path.isdir(dabs):
            for s in srcs:
                add(os.path.join(dest, os.path.basename(s.rstrip("/"))))
        else:
            add(dest)
    elif c == "sed" and any(a == "-i" or a.startswith("-i") for a in argv[1:]):
        for a in args:
            add(a, must_exist=True)
    elif c in ("tee", "rm"):
        for a in args:
            add(a)
    elif c == "unity" and len(argv) >= 3 and argv[1] == "command" and argv[2] in UNITY_WRITE:
        if argv[2] == "eval_file":
            for j, a in enumerate(argv):
                if a == "--file" and j + 1 < len(argv):
                    f = argv[j + 1]
                    fabs = f if os.path.isabs(f) else os.path.join(cwd, f)
                    try:
                        txt = open(fabs, encoding="utf-8", errors="ignore").read()
                    except OSError:
                        txt = ""
                    for m in re.finditer(r'["\'](' + ASSET_RE + r'[^"\'\n]+)["\']', txt):
                        add(m.group(1), must_exist=True)
        else:
            for a in args:
                if re.match(r"^" + ASSET_RE, a):
                    add(a, must_exist=True)

# 3) 인라인 스크립트의 쓰기
if re.search(r'open\([^)]*["\'][wax]\+?b?["\']|\.write_text\(|\.write_bytes\(|writeFileSync\(|\.write\(', cmd):
    for m in re.finditer(r'["\']((?:/|[A-Za-z]:/|' + ASSET_RE + r')[^"\'\n]+\.[A-Za-z0-9]+)["\']', cmd):
        add(m.group(1), must_exist=True)

# 정규화와 상대경로 해석
out, seen = [], set()
for p, must_exist in targets:
    p = p.replace("\\", "/")
    if os.path.isabs(p) or re.match(r"^[A-Za-z]:/", p):
        cands = [p]
    else:
        cands = [os.path.join(cwd, p), os.path.join(root, p)]
    pick = None
    for cnd in cands:
        n = os.path.normpath(cnd)
        if os.path.exists(n):
            pick = n
            break
    if pick is None:
        if must_exist:
            continue
        n = os.path.normpath(cands[0])
        if not os.path.isdir(os.path.dirname(n)):
            continue
        pick = n
    if pick not in seen:
        seen.add(pick)
        out.append(pick)
sys.stdout.write("\n".join(out))
