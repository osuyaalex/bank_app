"""Pulls the fallback source out of a captured trajectory.

Takes the fenced block that actually defines parseFallback, not simply the
first one: a model asked for a file will often restate the class it is
implementing against first, and taking block one yields a BankAlert
declaration that does not compile.
"""
import json, re, sys

traj, out = sys.argv[1], sys.argv[2]
text = ""
for line in open(traj):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    if ev.get("type") == "result" and isinstance(ev.get("result"), str):
        text = ev["result"]
    elif ev.get("type") == "assistant":
        for blk in ev.get("message", {}).get("content", []):
            if blk.get("type") == "text":
                text += blk["text"]

blocks = re.findall(r"```(?:dart)?\s*\n(.*?)```", text, re.S)
answer = next((b for b in blocks if "parseFallback" in b), None)
if answer is None:
    answer = max(blocks, key=len) if blocks else text
open(out, "w").write(answer.rstrip() + "\n")
print(f"wrote {out} ({len(answer.splitlines())} lines, from {len(blocks)} block(s))")
