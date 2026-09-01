The app below reads Nigerian bank SMS alerts with a hand-written parser.
Banks it has never been taught are not being read at all.

# What a candidate has to produce

Write one file. Nothing else is read, and nothing else is scored.

    agent/out/current/fallback.dart

It must contain exactly this, and it must compile:

```dart
import 'package:banking_app/parsing/bank_alert.dart';

/// Reads a bank alert the shipped parser could not.
///
/// Return null when this message is not a transaction, or when you have
/// nothing better to offer than the shipped parser did.
BankAlert? parseFallback(String sender, String body) {
  // your work here
}
```

## How it is used

For every case the harness calls **your `parseFallback` first**. The shipped
`parseAlert` is used only when yours returns null. So:

* Return null for anything you are not confident about. That hands the message
  back to the shipped parser, which already reads 29 formats correctly.
* You **can** break formats that currently work. Every one of those 29 is
  scored on the same run. Returning a half-filled alert for a Zenith or Wema
  message will cost you more than the held-out case you were aiming at.
* Messages that are not transactions must return null.

## How it is scored

A case passes only when **every** field is right:

| field          | rule |
|----------------|------|
| `detected`     | a transaction returns an alert; an advert, OTP or telco text returns null |
| `kind`         | `debit`, `credit` or `charge` |
| `amount`       | to the kobo |
| `occurredAt`   | to the minute; date-only messages are midnight |
| `counterpartyKey` | who was paid, run through `normaliseCounterparty` |
| `balanceAfter` | to the kobo, when the message carries one |

Partial credit does not exist. Finding the amount but filing it under the
wrong name has not helped the user.

## The fields

`BankAlert` is in `lib/parsing/bank_alert.dart`. It takes `bank`, `kind`,
`channel`, `narration` as required, then `amount`, `balanceAfter`,
`occurredAt`, `account`, `counterpartyKey`, `isReversal`.

Use `normaliseCounterparty()` from that file for the key. It is exported and
it is what the seen formats already use, so using anything else will disagree
with the rest of the app.


# The messages it cannot read

0 of 41 cases. For each, the message as it
arrives and what a correct parse looks like.

# Answer with

The complete contents of agent/out/current/fallback.dart in a single
```dart fenced block. No prose outside the block.
