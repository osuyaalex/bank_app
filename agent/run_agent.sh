#!/bin/zsh
# The agent: same prompt, plus the ability to check its own work.
#
# The only differences from ./agent/run_baseline.sh are the three that the
# comparison is about:
#
#   tools        it may read the repository and run the evaluator
#   iteration    it keeps going until the evaluator passes or turns run out
#   verification it is told to run the evaluator after every change, and that
#                the 29 working formats are scored on the same run
#
# The model, the prompt and the cases are identical.
#
#   ./agent/run_agent.sh
set -e
cd "${0:A:h}/.."

STAMP=$(date +%Y%m%d-%H%M%S)
TRAJ="agent/trajectories/agent-$STAMP.jsonl"
OUT="agent/out/agent"
mkdir -p "$OUT" agent/trajectories

echo "building the prompt..."
dart run agent/make_prompt.dart \
  agent/cases/dev.json agent/cases/negative.json agent/cases/seen.json \
  > agent/out/task_prompt.md

# Reset, so a run never inherits the previous one's answer.
cat > agent/out/current/fallback.dart <<'DART'
import 'package:banking_app/parsing/bank_alert.dart';

BankAlert? parseFallback(String sender, String body) => null;
DART

cat agent/out/task_prompt.md > agent/out/agent_prompt.md
cat >> agent/out/agent_prompt.md <<'EXTRA'

# How to work

You can check your own work. Do that rather than guessing.

1. Write your answer to `agent/out/current/fallback.dart`.
2. Run the evaluator:

       dart run agent/harness/run_with_fallback.dart \
         agent/cases/dev.json agent/cases/negative.json agent/cases/seen.json

   It prints every failing case with the field that is wrong, what was wanted
   and what it got.
3. Fix what failed and run it again. Keep going until nothing fails, or until
   you can explain why a case cannot be passed without breaking another.

Read `lib/parsing/bank_alert.dart` before you start. `BankAlert`,
`AlertKind`, `TxnChannel` and `normaliseCounterparty` all live there, and
using anything other than `normaliseCounterparty` for the key will disagree
with the rest of the app.

Watch the seen cases. They are formats that already work, and your fallback
is asked first, so a careless regular expression will take them down with it.
A drop there costs more than the held-out case you were reaching for.

Stop when the evaluator is clean. Do not edit anything except
`agent/out/current/fallback.dart`.
EXTRA

# The agent has Read and Glob. Telling it not to look at the test cases would
# be a request, not a guarantee, so the file leaves the working tree for the
# duration of the run and comes back afterwards.
SEALED=$(mktemp -d)
mv agent/cases/test.json "$SEALED/test.json"
restore() { mv "$SEALED/test.json" agent/cases/test.json 2>/dev/null || true; rmdir "$SEALED" 2>/dev/null || true; }
trap restore EXIT INT TERM

echo "agent: tools on, iterating against the evaluator..."
claude -p \
  --allowed-tools "Read,Write,Edit,Bash(dart run agent/harness/run_with_fallback.dart:*),Glob,Grep" \
  --max-turns 60 \
  --output-format stream-json --verbose \
  < agent/out/agent_prompt.md > "$TRAJ"

cp agent/out/current/fallback.dart "$OUT/fallback.dart" 2>/dev/null || true
echo "trajectory: $TRAJ"
echo
echo "scoring..."
dart run agent/harness/run_with_fallback.dart \
  agent/cases/dev.json agent/cases/negative.json agent/cases/seen.json || true
