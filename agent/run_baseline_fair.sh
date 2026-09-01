#!/bin/zsh
# The baseline, measured against the parser as it stood BEFORE the agent's
# work was merged.
#
# Once the merge landed, `lib/parsing/` already contained the answer. The
# prompt builder selects the cases the shipped parser fails, found none, and
# produced an empty task -- so a "baseline" run after the merge was really the
# merged parser scoring itself. This checks out the pre-merge parser for the
# duration and puts it back afterwards.
#
#   ./agent/run_baseline_fair.sh
set -e
cd "${0:A:h}/.."

PRE_MERGE=4fe0697   # the commit before "Read bank alerts that are written as sentences"
STAMP=$(date +%Y%m%d-%H%M%S)
TRAJ="agent/trajectories/baseline-fair-$STAMP.jsonl"
OUT="agent/out/baseline_fair"
mkdir -p "$OUT" agent/trajectories

git checkout $PRE_MERGE -- lib/parsing/
restore() { git checkout HEAD -- lib/parsing/ 2>/dev/null || true; }
trap restore EXIT INT TERM
echo "parser rolled back to $PRE_MERGE for the duration of this run"

dart run agent/make_prompt.dart \
  agent/cases/dev_train.json agent/cases/negative.json agent/cases/seen.json \
  > agent/out/task_prompt_fair.md
echo "cases in the prompt: $(grep -c '^## hold-' agent/out/task_prompt_fair.md)"

cat > agent/out/current/fallback.dart <<'DART'
import 'package:banking_app/parsing/bank_alert.dart';

BankAlert? parseFallback(String sender, String body) => null;
DART

echo "one prompt, no tools..."
set +e
# Denying the tools is not enough on its own. Twice the model answered with
# a hallucinated Read call written as plain text, invented the contents of the
# file, and ended its turn having produced nothing. It has to be told that
# there is nothing to read and that the prompt is complete.
claude -p \
  --append-system-prompt "You have no tools in this session. Do not attempt to read, search or run anything: any tool call you write will be text that does nothing, and the turn will end with no answer. Everything needed is in the prompt, including the full API you are writing against. Reply with the complete contents of the file in a single fenced dart block and no prose outside it." \
  --disallowedTools "Task,Bash,Edit,Write,Read,Glob,Grep,NotebookEdit,WebFetch,WebSearch,Skill,Workflow,ToolSearch,Monitor,SendMessage,ListAgents,TaskOutput,TaskStop,CronCreate,CronDelete,CronList,DesignSync,EnterWorktree,ExitWorktree,PushNotification,RemoteTrigger,ReportFindings,ScheduleWakeup,BashOutput,KillShell,SlashCommand,TodoWrite,ExitPlanMode,EnterPlanMode,Artifact,AskUserQuestion,SendFeedback,SendUserFile" \
  --max-turns 3 \
  --output-format stream-json --verbose \
  < agent/out/task_prompt_fair.md > "$TRAJ"
set -e

python3 - "$TRAJ" "$OUT/fallback.dart" <<'PY'
import json, re, sys
traj, out = sys.argv[1], sys.argv[2]
text = ""
for line in open(traj):
    line = line.strip()
    if not line: continue
    try: ev = json.loads(line)
    except json.JSONDecodeError: continue
    if ev.get("type") == "result" and isinstance(ev.get("result"), str):
        text = ev["result"]
    elif ev.get("type") == "assistant":
        for blk in ev.get("message", {}).get("content", []):
            if blk.get("type") == "text":
                text += blk["text"]
m = re.search(r"```dart\s*\n(.*?)```", text, re.S)
open(out, "w").write((m.group(1) if m else text).rstrip() + "\n")
print(f"wrote {out} ({len((m.group(1) if m else text).splitlines())} lines)")
PY

cp "$OUT/fallback.dart" agent/out/current/fallback.dart
echo
echo "=== baseline vs the PRE-MERGE parser, on cases it has never seen ==="
dart run agent/harness/run_with_fallback.dart agent/cases/test.json || true
echo "=== regression ==="
dart run agent/harness/run_with_fallback.dart agent/cases/seen.json agent/cases/negative.json 2>&1 | grep -E "fully correct|failed"
