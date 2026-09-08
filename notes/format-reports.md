# Bank formats users have reported

Where the reports go, and how to read them.

## Where they land

Firestore, top-level collection **`format_reports`**, one document per report.

```
format_reports/{autoId}
  shapes      [map]      {sender, shape} per distinct format
  senders     [string]   the sender ids, flat, for finding reports by bank
  uid         string     who sent it, so a follow-up is possible
  email       string?    only if they asked to be told when their bank works
  note        string?    reserved; nothing writes it yet
  appVersion  string?    which build produced the report
  createdAt   timestamp  server time
  status      string     'new' until you change it
```

## How to read them

**Firebase console → Firestore → `format_reports`**, sorted by `createdAt`
descending. That is the whole workflow; there is nothing to install.

The app cannot read this collection. `firestore.rules` denies `read` outright,
because one user must never be able to list what another has sent. If you ever
want this programmatically, it needs a service account and the Admin SDK , the
client is deliberately write-only.

## What a report actually contains

The shape, and nothing else. `lib/data/sms_shape.dart` runs on the device
before anything is sent:

```
Acct:2211234558                    Acct:##########
DT:23/08/2026 09:06:35 PM          DT:##/##/#### ##:##:## PM
NIP CR/MOB/ABUBAKAR ALIYU/PAL  ->  NIP CR/MOB/<name> <name>/<w>
DR Amt:300.00                      DR Amt:###.##
Bal:142.92                         Bal:###.##
```

Every digit becomes `#`. Every word that is not bank vocabulary becomes
`<name>` or `<w>`. What survives is the labels, the separators, the keywords,
the order, the date format and the direction marker , which is the entire
input to writing a parser rule.

The redaction is an **allow-list**, deliberately: a deny-list of "things that
look like names" fails silently the first time somebody is called something it
has not heard of, and a redactor that fails silently is worse than none,
because its output looks safe. `looksRedacted` checks the result again before
the write and drops anything that fails.

## Turning a report into a fix

1. Take a shape from the report and fill the `#`s back in with plausible
   figures and the `<name>`s with invented names. The numbers never mattered;
   the layout is the format.
2. Add it to `agent/cases/` (on `agent-parser-repair`) as a held-out case with
   the expected amount, direction, date, counterparty and balance.
3. Run the agent against it, or write the rule by hand.
4. `dart run agent/evaluate.dart agent/cases/test.json` to confirm nothing else
   broke.
5. If they left an email, tell them.

## Before this ships

Three things that are not code:

- **Play Data Safety form** , declare that the app collects and transmits this,
  what it is, and that it is optional.
- **Privacy policy** , `bank-ai.netlify.app/policy` needs a clause covering it.
- **In-app disclosure** , the sheet itself is the disclosure. It shows the exact
  payload before asking, which is what makes the consent real. Do not replace
  that preview with a summary.

The app holds `READ_SMS`, which Play treats as a restricted permission, so the
bar for transmitting anything derived from SMS is high. Sending only the shape,
never a message body, is what keeps this on the right side of it.
