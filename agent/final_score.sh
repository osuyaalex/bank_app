#!/bin/zsh
# The measurement. Run once, at the end, on cases no candidate has seen.
#
#   ./agent/final_score.sh baseline
#   ./agent/final_score.sh agent
#
# The test cases are never in a prompt and are moved out of the working tree
# while the agent runs. This is the only number that says anything about
# whether the solution generalises to the next bank that changes its wording.
set -e
cd "${0:A:h}/.."
WHICH=${1:?usage: ./agent/final_score.sh <baseline|agent|shipped>}

if [[ "$WHICH" == "shipped" ]]; then
  cat > agent/out/current/fallback.dart <<'DART'
import 'package:banking_app/parsing/bank_alert.dart';
BankAlert? parseFallback(String sender, String body) => null;
DART
else
  cp "agent/out/$WHICH/fallback.dart" agent/out/current/fallback.dart
fi

echo "=== $WHICH : UNSEEN TEST SET ==="
dart run agent/harness/run_with_fallback.dart agent/cases/test.json || true
echo
echo "=== $WHICH : REGRESSION (formats that already worked) ==="
dart run agent/harness/run_with_fallback.dart \
  agent/cases/seen.json agent/cases/negative.json || true
