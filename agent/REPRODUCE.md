# Reproducing this

Written for someone starting from nothing. Every command is meant to be
copied as it appears.

## What you need

| | version used | why |
|---|---|---|
| Flutter | 3.x (`flutter --version`) | brings the Dart SDK the parser is written in |
| Dart | 3.x, comes with Flutter | every tool here is a Dart script |
| Claude Code | 2.1.251 (`claude --version`) | the agent, and the baseline |
| macOS or Linux | | the shell scripts are zsh |

Claude Code must be signed in. Check with:

    claude --version && echo "signed in: $(claude -p 'reply with OK' --allowed-tools 'NoSuchTool' --max-turns 2)"

No API key is set or needed; the runs go through a Claude subscription.

## Setup

    git clone <this repository>
    cd bank_app
    flutter pub get

That is the whole setup. The evaluation has no dependencies beyond the app's
own.

## The data

Two kinds, and only one of them is in the repository.

**In the repository** — `agent/cases/*.json`, 51 cases. Seventeen real
formats and twelve real non-transactions, both anonymised; twelve authored
bank formats for training and ten held back for the measurement. Everything
needed to reproduce the headline number is here.

**Not in the repository** — the private corpus: 5,401 SMS from the author's
phone, of which 2,419 are from banks. It is used for two things, both
optional: regenerating the anonymised cases, and giving the agent a real-
traffic check. Every tool that wants it degrades gracefully when it is
absent, so you can reproduce the main result without it.

If you have an Android phone with Nigerian bank alerts on it and want the
full experience:

    adb shell content query --uri content://sms --projection "address:date:body" \
      > ~/bank-sms-dump.txt
    dart run agent/build_cases.dart ~/bank-sms-dump.txt

That rewrites `agent/cases/seen.json` and `negative.json` from your own
messages, anonymised. Names, account numbers and phone numbers are replaced
consistently, so one real person becomes one invented person throughout.

## The main result, in one command

    dart run agent/evaluate.dart agent/cases/test.json

    cases            25
    fully correct    21   (84.0%)
    held-out banks   21/25

Twenty-five bank formats the parser was never taught. Twenty-one read
correctly, against seventeen before the agent's work went in.

To see what the parser scored before the agent's work went in:

    git stash          # if you have local changes
    git checkout 4fe0697 -- lib/parsing/
    dart run agent/evaluate.dart agent/cases/test.json    # 17/25
    git checkout HEAD -- lib/parsing/

Runtime: under five seconds. Cost: nothing.

## Checking nothing was broken

    flutter test
    # 292 tests, all pass

    dart run agent/evaluate.dart agent/cases/seen.json agent/cases/negative.json
    # 29/29

The second is the important one. It holds seventeen formats that already
worked and twelve messages that carry amounts but are not transactions --
adverts, one-time passwords, telco balance texts. A parser that gets greedy
shows up here immediately.

## Running the candidates yourself

Both cost money and take minutes rather than seconds. Neither is needed to
check the result above; they are how that result was produced.

    ./agent/run_baseline_fair.sh   # ~4 min,   ~$1   (rolls lib/parsing back to 4fe0697 first)
    ./agent/run_agent_v3.sh     # ~23 min,  ~$8

Each writes a trajectory to `agent/trajectories/` and an artefact to
`agent/out/<name>/fallback.dart`. Then:

    ./agent/final_score.sh baseline
    ./agent/final_score.sh agent_v3
    ./agent/final_score.sh shipped     # the parser on its own

`final_score.sh` is the only script that touches `agent/cases/test.json`. The
two runner scripts move that file out of the working tree before starting,
because the agent has `Read` and `Glob` and asking it not to look would be a
request rather than a guarantee.

## What you should see

| | 25 unseen | regression | turns | cost | wall clock |
|---|---|---|---|---|---|
| shipped parser, before | 17/25 | 29/29 | -- | -- | -- |
| baseline: one prompt, no tools | 18/25 | 29/29 | 1 | $0.96 | 4 min |
| agent v3 | 21/25 | 29/29 | 74 | $7.60 | 23 min |

On the ten cases the work was done against: shipped 5/10, baseline 5/10,
agent v1 5/10, agent v2 6/10, agent v3 7/10.

Language models are not deterministic. Expect the same shape and a case or
two of movement, not the same numbers to the decimal. If you want to inspect
the exact runs behind the table rather than reproduce them, the trajectories
in `agent/trajectories/` are complete.

## The other two checks

    dart run agent/harness/val_score.dart      # needs a copy at agent/cases/.val_sealed.json
    dart run agent/harness/corpus_probe.dart   # needs ~/bank-sms-dump.txt

The first reports a bare count on four banks the agent never sees -- no ids,
no fields, no expected values. The second runs a candidate over the real
corpus and reports crashes, messages newly read, and disagreements with a
parser already right about 2,367 of them. Neither has an answer key, which is
the point of both.

## A note on the trajectories

They are unedited except for one thing: `agent/scrub_trajectories.dart`
blanks digit runs of six or more, because an early version of the case files
carried a real phone number that the anonymiser missed -- it required a word
boundary, and `AirtimeALATMTN07068808118` has none. The case files were fixed
and regenerated; the logs are a record of runs that already happened. Epoch
timestamps are preserved. Nothing else in them was altered.
