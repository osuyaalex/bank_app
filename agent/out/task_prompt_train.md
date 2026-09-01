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

7 of 41 cases. For each, the message as it
arrives and what a correct parse looks like.

## hold-004  (KUDA)
sender: Kuda
body:
```
You sent NGN2,000.00 to CHINEDU EZE on 12 Jul 2026, 10:45. Your balance is NGN18,300.00
```
expected: kind=debit amount=2000.0 date=2026-07-12T10:45:00.000 counterparty=CHINEDU EZE balance=18300.0

## hold-005  (OPAY)
sender: OPay
body:
```
Credit Alert! You received NGN15,000.00 from HALIMA IBRAHIM. Bal: NGN33,500.00. 12/07/2026 16:20
```
expected: kind=credit amount=15000.0 date=2026-07-12T16:20:00.000 counterparty=HALIMA IBRAHIM balance=33500.0

## hold-008  (STERLING)
sender: Sterling
body:
```
Sterling Bank Alert
DR NGN25,000.00
ACC: ***7788
NARRATION: NIP/TRF/FUNMILAYO ADEBAYO
12-Jul-26 13:05
BAL: NGN102,300.00
```
expected: kind=debit amount=25000.0 date=2026-07-12T13:05:00.000 counterparty=FUNMILAYO ADEBAYO balance=102300.0

## hold-012  (VBANK)
sender: VBank
body:
```
You paid NGN8,500 at PRINCE EBEANO SUPERMARKET on 20-Aug-2026 17:22. Balance: NGN33,180.45
```
expected: kind=debit amount=8500.0 date=2026-08-20T17:22:00.000 counterparty=PRINCE EBEANO SUPERMARKET balance=33180.45

## hold-013  (JAIZ)
sender: Jaiz
body:
```
NGN12,000 was received from OBIOMA PEDRO into your account ***2020 on 20 Aug 2026 at 11:05. Bal NGN60,000
```
expected: kind=credit amount=12000.0 date=2026-08-20T11:05:00.000 counterparty=OBIOMA PEDRO balance=60000.0

## hold-014  (GLOBUS)
sender: Globus
body:
```
Payment of NGN4,300.00 made to UBER TRIP on 20/08/2026 19:40. Available balance NGN15,700.00
```
expected: kind=debit amount=4300.0 date=2026-08-20T19:40:00.000 counterparty=UBER TRIP balance=15700.0

## hold-015  (TITANTRUST)
sender: TitanTrust
body:
```
REVERSED: NGN2,500 has been returned to acct ***6060 on 20-Aug-2026. Bal NGN18,200
```
expected: kind=credit amount=2500.0 date=2026-08-20T00:00:00.000 counterparty=- balance=18200.0

# Answer with

The complete contents of agent/out/current/fallback.dart in a single
```dart fenced block. No prose outside the block.
