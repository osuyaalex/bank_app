#!/bin/zsh
# The agent, third iteration. Everything the first two runs said was missing.
#
#   v1  tools + iteration, checked against the cases it was taught     5/10 test
#   v2  plus a held-out validation count it could not fit              6/10 test
#   v3  plus:
#         - four sentence-style training cases. v1 and v2 learned
#           "banks write labelled forms" because eleven of twelve examples
#           were, and every remaining test failure is a bank writing English.
#         - the real corpus: 5,401 unlabelled messages it can check itself
#           against for crashes and for disagreements with a parser that
#           already reads 2,367 of them correctly.
#         - room to finish. v2 stopped at the 60-turn ceiling mid-work.
#
#   ./agent/run_agent_v3.sh
set -e
cd "${0:A:h}/.."

STAMP=$(date +%Y%m%d-%H%M%S)
TRAJ="agent/trajectories/agent-v3-$STAMP.jsonl"
OUT="agent/out/agent_v3"
mkdir -p "$OUT" agent/trajectories

echo "building the prompt (training cases only)..."
dart run agent/make_prompt.dart \
  agent/cases/dev_train.json agent/cases/negative.json agent/cases/seen.json \
  > agent/out/task_prompt_train.md

cat > agent/out/current/fallback.dart <<'DART'
import 'package:banking_app/parsing/bank_alert.dart';

BankAlert? parseFallback(String sender, String body) => null;
DART

cat agent/out/task_prompt_train.md > agent/out/agent_v3_prompt.md
cat >> agent/out/agent_v3_prompt.md <<'EXTRA'

# The one thing worth knowing before you start

Nigerian banks write alerts in two completely different ways, and a parser
that only handles one of them looks finished while missing half the country.

**As a form**, with labels:

    Amt: NGN5,000.00
    Desc: TRF/ADAEZE OKAFOR/RENT
    Bal: NGN128,430.55

**As a sentence**, with none:

    You paid NGN8,500 at PRINCE EBEANO SUPERMARKET on 20-Aug-2026 17:22.

In a sentence the direction is a verb, the counterparty follows a preposition,
and there may be no labels at all. Amounts are often whole naira with no
decimal places and no thousands separator, which makes them look like
reference numbers. Handle both shapes. Do not assume a label exists.

# How to check yourself

Three signals. They tell you different things and you need all three.

**1. Training cases — full detail.** Every failure, the field, wanted and got.

    dart run agent/harness/run_with_fallback.dart \
      agent/cases/dev_train.json agent/cases/negative.json agent/cases/seen.json

**2. Validation — a count and nothing else.** Four banks you have not been
shown. Not which ones, not which field, not what was expected.

    dart run agent/harness/val_score.dart

This is the only evidence you have about whether your rules work on a bank
nobody has described to you, which is the actual job. A rule that lifts
training and leaves this flat is a rule that fits these twelve messages rather
than the way banks write.

**3. Real traffic — 5,401 unlabelled messages off a real phone.**

    dart run agent/harness/corpus_probe.dart

No answer key, and it does not need one. It reports crashes, how many messages
you newly read, and — most usefully — how often you *disagree* with the
shipped parser on messages it already reads correctly. It is right about 2,367
of them. Every disagreement is a bug in one of you, and it is almost always
yours. Run this after any change to a pattern that could match broadly.

Read `lib/parsing/bank_alert.dart` first. `BankAlert`, `AlertKind`,
`TxnChannel` and `normaliseCounterparty` live there; use
`normaliseCounterparty` for the key or you will disagree with the rest of the
app.

Stop when training is clean, validation is as high as you can get it, and the
corpus probe shows no crashes and no disagreements. Edit only
`agent/out/current/fallback.dart` and create no other files.
EXTRA

SEALED=$(mktemp -d)
mv agent/cases/test.json "$SEALED/test.json"
mv agent/cases/dev.json "$SEALED/dev.json"
# The validation cases must be scoreable but not readable: the scorer
# reads a dotfile copy, and the human-readable original is sealed.
cp agent/cases/dev_val.json agent/cases/.val_sealed.json
mv agent/cases/dev_val.json "$SEALED/dev_val.json"
restore() {
  for f in test dev dev_val; do
    mv "$SEALED/$f.json" "agent/cases/$f.json" 2>/dev/null || true
  done
  rm -f agent/cases/.val_sealed.json
  rmdir "$SEALED" 2>/dev/null || true
}
trap restore EXIT INT TERM

echo "agent v3: 12 training cases, a blind validation count, and real traffic..."
# The agent exits non-zero when it runs out of turns. Under `set -e` that
# aborted v2 before its work was saved, which is how a completed run came back
# looking empty.
set +e
claude -p \
  --allowed-tools "Read,Write,Edit,Glob,Grep,Bash(dart run agent/harness/run_with_fallback.dart:*),Bash(dart run agent/harness/val_score.dart:*),Bash(dart run agent/harness/corpus_probe.dart:*)" \
  --max-turns 120 \
  --output-format stream-json --verbose \
  < agent/out/agent_v3_prompt.md > "$TRAJ"
CLAUDE_EXIT=$?
set -e
echo "claude exit: $CLAUDE_EXIT"

cp agent/out/current/fallback.dart "$OUT/fallback.dart"
echo "trajectory: $TRAJ"
echo "artefact:   $OUT/fallback.dart"
