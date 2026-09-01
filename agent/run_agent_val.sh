#!/bin/zsh
# The agent, with a validation signal it cannot fit.
#
# Same as ./agent/run_agent.sh except for what it is allowed to measure:
#
#   iterate on   8 training cases, full failure detail, expected values in the prompt
#   check on     4 validation cases it never sees -- a count only, no ids, no fields
#
# The previous run showed the agent converging on the cases it could see and
# generalising no better than one prompt with no tools. This asks whether the
# problem was iteration itself or the signal it was iterating against.
#
#   ./agent/run_agent_val.sh
set -e
cd "${0:A:h}/.."

STAMP=$(date +%Y%m%d-%H%M%S)
TRAJ="agent/trajectories/agent-val-$STAMP.jsonl"
OUT="agent/out/agent_val"
mkdir -p "$OUT" agent/trajectories

echo "building the prompt (training cases only)..."
dart run agent/make_prompt.dart \
  agent/cases/dev_train.json agent/cases/negative.json agent/cases/seen.json \
  > agent/out/task_prompt_train.md

cat > agent/out/current/fallback.dart <<'DART'
import 'package:banking_app/parsing/bank_alert.dart';

BankAlert? parseFallback(String sender, String body) => null;
DART

cat agent/out/task_prompt_train.md > agent/out/agent_val_prompt.md
cat >> agent/out/agent_val_prompt.md <<'EXTRA'

# How to work

You have two ways to check yourself, and they tell you different things.

**1. The training cases.** Full detail: every failing case, the field that is
wrong, what was wanted and what you produced.

    dart run agent/harness/run_with_fallback.dart \
      agent/cases/dev_train.json agent/cases/negative.json agent/cases/seen.json

**2. The validation cases.** Four messages from banks you have not been shown.
You get a count and nothing else — not which ones, not which field, not what
was expected.

    dart run agent/harness/val_score.dart

Read that second number carefully. It is the only evidence you have about
whether your rules work on a bank nobody has described to you, which is the
actual job: the next format change will arrive with no worked example
attached.

A rule that lifts the training score and leaves validation flat is a rule that
fits these eight messages rather than the way Nigerian banks write. Prefer the
general shape over the specific string. If training is perfect and validation
is not, keep working on validation.

Read `lib/parsing/bank_alert.dart` first. `BankAlert`, `AlertKind`,
`TxnChannel` and `normaliseCounterparty` live there; use
`normaliseCounterparty` for the key or you will disagree with the rest of the
app.

Watch the seen cases. Your fallback is asked before the shipped parser, so a
careless pattern takes working formats down with it.

Stop when both numbers are as high as you can get them. Edit only
`agent/out/current/fallback.dart`.
EXTRA

# The test cases leave the tree: the agent has Read and Glob, and asking it not
# to look would be a request rather than a guarantee.
SEALED=$(mktemp -d)
mv agent/cases/test.json "$SEALED/test.json"
mv agent/cases/dev.json "$SEALED/dev.json"
restore() {
  mv "$SEALED/test.json" agent/cases/test.json 2>/dev/null || true
  mv "$SEALED/dev.json" agent/cases/dev.json 2>/dev/null || true
  rmdir "$SEALED" 2>/dev/null || true
}
trap restore EXIT INT TERM

echo "agent: iterating on 8, validating against 4 it cannot see..."
claude -p \
  --allowed-tools "Read,Write,Edit,Glob,Grep,Bash(dart run agent/harness/run_with_fallback.dart:*),Bash(dart run agent/harness/val_score.dart:*)" \
  --max-turns 60 \
  --output-format stream-json --verbose \
  < agent/out/agent_val_prompt.md > "$TRAJ"

cp agent/out/current/fallback.dart "$OUT/fallback.dart" 2>/dev/null || true
echo "trajectory: $TRAJ"
