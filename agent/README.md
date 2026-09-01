# Teaching a parser a bank it has never seen

A coding agent that repairs a production SMS parser when a Nigerian bank
changes its wording, and the evaluation that says whether it actually helps.

---

## Who has this problem

Me, and anyone else maintaining a parser against formats they do not control.

I ship a budgeting app on the Play Store. It reads the SMS alerts Nigerian
banks send after every transaction and turns them into a spending record. It
does this with a hand-written parser: no model, no network, nothing about your
salary leaving the phone.

That decision was measured, not assumed. An earlier version of the app sent
every alert to Gemini. Over the same 5,348 messages from my phone, the model
found 1,270 transactions leaving the account and the parser found 1,271. On
the job the app exists to do, they tied — so the model came out, along with
its per-transaction cost, its network dependency and the privacy problem of
posting somebody's bank alerts to a third party.

## What bottleneck makes it worth solving

A parser only knows the formats you teach it.

Banks change their wording without telling anybody. When that happens the app
does not crash and does not warn: the message simply stops being recognised,
and the user's spending quietly goes missing. I find out when somebody
complains.

Fixing it by hand means reading the new message, working out which of its
twenty-six date formats applies, writing a rule, and not breaking the other
twenty-five while doing it. The last part is the expensive part. A regular
expression written to catch one bank is very good at silently eating another.

## Does the agent solve it well

That is what this directory measures, on cases the agent never sees.

---

## The evaluation

Three sets of cases, 51 in total.

| set | n | where it comes from | what it is for |
|---|---|---|---|
| `cases/seen.json` | 17 | my real inbox, anonymised | formats that already work. Regression guard. |
| `cases/negative.json` | 12 | my real inbox, anonymised | adverts, OTPs and telco balance texts that carry amounts and must be ignored |
| `cases/dev.json` | 12 | authored from public formats | banks the parser was never taught. **Both candidates see these.** |
| `cases/test.json` | 10 | authored from public formats | banks neither candidate ever sees. **The measurement.** |

### Scoring is all-or-nothing

A case passes only when detection, kind, amount, date, counterparty and
balance are *all* correct. There is no partial credit, because there is no
partial credit for the user: an app that finds the amount and files it under
the wrong name has not helped anybody.

### Why there is a dev/test split

The first version of this evaluation had one set of unseen banks, and both
candidates were scored on it. The baseline got 12 out of 12 on its first
attempt with no tools, which looked like proof that the whole agentic loop was
unnecessary.

It was not. Splitting the cases showed the baseline scoring 12/12 on the cases
it had been shown and 5/10 on cases it had not — the same as the hand-written
parser it was supposed to improve on. It had fitted the shapes in front of it
and generalised nothing.

Only the test set is reported as a result. It is moved out of the working tree
while the agent runs, because the agent has `Read` and `Glob`, and asking it
not to look would be a request rather than a guarantee.

### Where the data comes from

The real corpus is 5,401 messages from my own phone, 2,419 of them from banks.
It is never committed. `build_cases.dart` reads it and writes the publishable
cases, replacing every personal name, account number and phone number —
consistently, so one real person always becomes the same invented person and
counterparty grouping still means something. Brand names are kept.

The dev and test cases are authored from the public alert formats of banks I
do not hold accounts with. They are representative, not captured. Said plainly
here because it matters: no real customer of GTBank, Access, UBA, Kuda, OPay,
Moniepoint, PalmPay, Sterling, FCMB, Ecobank, Fidelity, Union, Stanbic,
Polaris, Providus, Carbon, Sparkle or Keystone had their messages read.

---

## The two candidates

Both are Claude Code, given the same prompt built by the same command from the
same cases. Three things differ, and they are the three things this experiment
is about.

| | baseline | agent |
|---|---|---|
| tools | none | Read, Write, Edit, Glob, Grep, and the evaluator |
| turns | 3 | up to 60 |
| verification | none | told to run the evaluator after every change |

Disabling the tools took three attempts. `--allowedTools ""` does **not**
disable them: the first two baseline runs quietly read the repository and ran
the evaluator, which is exactly the advantage a baseline may not have. An
allow-list matching nothing plus an explicit deny list does work, and the
trajectories show zero tool calls.

Both write the same artefact, `out/current/fallback.dart`, which the harness
consults **before** the shipped parser. That ordering is deliberate: a
fallback that could only speak where the shipped parser was silent could never
correct a message that parses wrongly, and could never break anything either,
which would make the regression cases decoration.

---

## Results

Reported on `cases/test.json`, which no candidate has seen.

| | test, unseen | regression | turns | cost |
|---|---|---|---|---|
| shipped parser, before any of this | 5/10 | 29/29 | -- | -- |
| baseline: one prompt, no tools | 5/10 | 29/29 | 1 | $0.96 |
| agent v1: tools and iteration | 5/10 | 29/29 | 12 | $1.74 |
| agent v2: plus a validation count it cannot fit | 6/10 | 29/29 | 61 | $7.95 |
| **agent v3: plus the shape of the problem and real traffic** | **7/10** | 29/29 | 74 | $7.60 |

**+40% over a fair baseline.** Fair took four attempts: the first run had
tools it should not have had, the second was handed an empty prompt, the third
hallucinated a file read and answered nothing, and the fourth guessed the enum
names because the API it was told to write against was not actually in the
prompt. Every one of those bugs made the baseline weaker than it should have
been, which is the easiest way in the world to manufacture an improvement. The
figure above is the fifth run, with zero tool calls in its trajectory.

The baseline also repeats the overfitting signature exactly: **12/12 on the
cases it was shown, 5/10 on the ten it was not.**

Nothing broken, with nothing broken: the 29 formats that
already worked still work, and across 5,401 real messages there are no
crashes and not one message newly misread.

### And it shipped

The rules that earned their place are merged into the app, in
`lib/parsing/generic_sentence.dart`. All 292 of the app's own tests pass. A
user whose bank writes sentences stops losing payments; nothing else about
the app changes.

The largest single obstacle turned out not to be in the agent's code at all.
`classifyAlert` looks for the vocabulary of a labelled alert -- `DR`, `CR`,
"debited", an `Amt:` field -- and a sentence carries none of it, so
`parseAlert` returned null before any parser was reached. The agent's work
scored 6/10 in place until that dispatch was widened. Merging is not
copying.

---

## Improvement changelog

| stage | what was tried and why | evidence | decision |
|---|---|---|---|
| Baseline | One prompt, no tools, one turn: the "paste it into a chat window" approach | 12/12 on the cases it was shown, 5/10 on the ten it was not, 29/29 regression | Kept as the comparison. It writes 487 lines of real parser -- no hard-coded answers -- and still generalises no better than the parser it was replacing. |
| Fix 1 | First baseline run used Bash and Read despite `--allowedTools ""` | trajectory showed tool calls | Denied every tool by name and verified zero calls. A baseline with tools is not a baseline. |
| Fix 2 | Fallback ran only when the shipped parser returned null, so cases that parsed *wrongly* were unreachable | ceiling of 10/12 by construction | Gave the fallback precedence. Side effect: the 29 working formats are now genuinely at risk every run. |
| Fix 3 | One set of unseen banks, scored for everyone | baseline hit 12/12 first try — no headroom, and apparently no need for an agent at all | Split dev from test. Baseline held at 12/12 dev but fell to 5/10 test: it had fitted the shapes it was shown. **The result would have been the opposite of the truth without this.** |
| Agent v1 | Same prompt, plus tools, iteration and instructions to verify | 5/10 test, identical to the baseline, failing the same five cases | Kept, but it bought nothing. Its loop could only run on the cases it had been taught, so it converged on those faster and generalised no better. |
| Agent v2 | Gave it four banks it never sees, reported as a bare count -- no ids, no fields, no expected values | 6/10 test | Kept. The first thing that moved the number. It ran out of turns still working. |
| Fix 4 | v2 hit the turn ceiling and `set -e` aborted the script before saving, so a finished run looked empty | artefact was on disk the whole time | Raised to 120 turns and stopped treating a non-zero exit as fatal. |
| Fix 5 | Eleven of twelve training cases were labelled forms, so both candidates learned "banks write forms". Every remaining failure was a bank writing English. | -- | Added four sentence-style training cases and one line telling it banks write two ways. Phrasings deliberately not shared with the test set; the only overlap is the generic label `Available bal`. |
| Agent v3 | All of the above, plus 5,401 unlabelled real messages to check itself against for crashes and for disagreements with a parser already right about 2,367 of them | 7/10 test, 29/29 regression, 0 crashes, 0 disagreements | **Kept and merged into the app.** |
| Merge | Folding the agent's rules into `lib/parsing/` | 6/10 in place, not 7/10 | `classifyAlert` was discarding sentence-shaped messages before any parser saw them. Widening the dispatch restored 7/10 and all 292 app tests pass. |

---

## Reproduction

See [REPRODUCE.md](REPRODUCE.md). The headline number is one command and takes
five seconds:

    dart run agent/evaluate.dart agent/cases/test.json

## Hot take

**An agent's verification loop is worth exactly as much as the evaluation you
hand it.**

Giving the agent tools and letting it iterate bought nothing. v1 had a full
loop -- write, run the evaluator, read the failures, fix, repeat -- and scored
identically to a single prompt with no tools at all, failing the same five
cases. It was not idle. It ran the evaluator five times and converged
faster than the baseline did. It converged on the twelve cases it had been
shown.

That is the failure mode, and it is quiet. A loop that checks itself against
its own training signal looks like rigour and behaves like memorisation. The
more turns you give it, the better it gets at the examples you already had and
the less any of it means.

What moved the number was changing what the agent could measure. First a score
on four banks it could not see, reported as a bare count -- no ids, no fields,
nothing to fit. Then 5,401 unlabelled real messages, where the useful question
is not "is this right" but "do I disagree with a parser that is already right
about 2,367 of them". Neither has an answer key. Both improved generalisation
where iteration alone did not.

The same trap nearly took this evaluation down with it. With one set of unseen
banks, the baseline scored 12/12 on its first attempt and appeared to prove the
whole exercise pointless. Splitting the cases showed it scoring 12/12 on what
it had been shown and 5/10 on what it had not. **Without that split, this
project would have reported the exact opposite of the truth** -- and it would
have had a clean, evidenced, entirely wrong result to show for it.

So: before asking whether your agent is good, ask what it is allowed to check
itself against. If the answer is "the examples I gave it", you have not built
a verification loop. You have built a faster overfitter.

## A disclosure

The first version of this app, in early 2025, sent every bank alert to Gemini.
That API key is hardcoded in commit `a4e09d1` of this repository's history. It
was revoked before this submission. It is mentioned here rather than left to
be discovered: the key is dead, the current app makes no network calls while
parsing, and `lib/firebase network/keys.dart` reads from the environment.

The `AIza...` strings in `google-services.json` and `firebase_options.dart`
are Firebase client configuration, which is public by design -- they identify
the project and authorise nothing. Access is controlled by Firestore rules and
App Check.
