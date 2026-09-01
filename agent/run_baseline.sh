#!/bin/zsh
# The baseline: one direct prompt, no tools, one turn.
#
# This is the "reasonable basic way to handle the task" the rules ask for --
# what you get from pasting the failing messages into a chat window and asking
# for a parser. It sees the same prompt as the agent and nothing else: it
# cannot read the repository, cannot run the evaluator and cannot iterate.
#
#   ./agent/run_baseline.sh
set -e
cd "${0:A:h}/.."

STAMP=$(date +%Y%m%d-%H%M%S)
TRAJ="agent/trajectories/baseline-$STAMP.jsonl"
OUT="agent/out/baseline"
mkdir -p "$OUT" agent/trajectories

echo "building the prompt..."
dart run agent/make_prompt.dart \
  agent/cases/dev.json agent/cases/negative.json agent/cases/seen.json \
  > agent/out/task_prompt.md

echo "one prompt, no tools, one turn..."
# Every tool named in the session init is denied by name. An empty
# --allowedTools does NOT disable tools; the first run of this script proved
# that by reading the repository and running the evaluator, which is exactly
# the advantage the baseline is not allowed to have.
# Tools are disabled by giving an allow-list that matches nothing. An empty
# --allowedTools does NOT disable them: the first run of this script read the
# repository and ran the evaluator, which is precisely the advantage the
# baseline must not have. The deny list is belt and braces.
claude -p \
  --allowed-tools "NoSuchTool" \
  --disallowedTools "Task,Bash,Edit,Write,Read,Glob,Grep,NotebookEdit,WebFetch,WebSearch,Skill,Workflow,ToolSearch" \
  --max-turns 3 \
  --output-format stream-json --verbose \
  < agent/out/task_prompt.md > "$TRAJ"

python3 - "$TRAJ" "$OUT/fallback.dart" <<'PY'
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
m = re.search(r"```dart\s*\n(.*?)```", text, re.S)
code = m.group(1) if m else text
open(out, "w").write(code.rstrip() + "\n")
print(f"wrote {out}  ({len(code.splitlines())} lines)")
PY

cp "$OUT/fallback.dart" agent/out/current/fallback.dart
echo "trajectory: $TRAJ"
echo
echo "scoring..."
dart run agent/harness/run_with_fallback.dart \
  agent/cases/dev.json agent/cases/negative.json agent/cases/seen.json || true
