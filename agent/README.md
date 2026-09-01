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

| | dev (shown) | test (unseen) | regression |
|---|---|---|---|
| shipped parser | 7/12 | 5/10 | 29/29 |
| baseline, one prompt | 12/12 | 5/10 | 29/29 |
| agent | _pending_ | _pending_ | _pending_ |

---

## Improvement changelog

| stage | what was tried and why | evidence | decision |
|---|---|---|---|
| Baseline | One prompt, no tools, one turn: the "paste it into a chat window" approach | 12/12 dev, 5/10 test | Kept as the comparison |
| Fix 1 | First baseline run used Bash and Read despite `--allowedTools ""` | trajectory showed tool calls | Denied every tool by name and verified zero calls. A baseline with tools is not a baseline. |
| Fix 2 | Fallback ran only when the shipped parser returned null, so cases that parsed *wrongly* were unreachable | ceiling of 10/12 by construction | Gave the fallback precedence. Side effect: the 29 working formats are now genuinely at risk every run. |
| Fix 3 | One set of unseen banks, scored for everyone | baseline hit 12/12 first try — no headroom, and apparently no need for an agent at all | Split dev from test. Baseline held at 12/12 dev but fell to 5/10 test: it had fitted the shapes it was shown. **The result would have been the opposite of the truth without this.** |
| Agent | Same prompt, plus tools, iteration and instructions to verify | _pending_ | _pending_ |

---

## Reproduction

_pending_

## Hot take

_pending_
