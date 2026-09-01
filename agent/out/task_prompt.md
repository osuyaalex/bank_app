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

5 of 41 cases. For each, the message as it
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

## hold-006  (MONIEPOINT)
sender: Moniepoint
body:
```
POS Purchase
Amount: NGN6,800.00
Merchant: TOTAL ENERGIES ABUJA
Date: 12-07-2026 11:11
Balance: NGN9,420.00
```
expected: kind=debit amount=6800.0 date=2026-07-12T11:11:00.000 counterparty=TOTAL ENERGIES ABUJA balance=9420.0

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

## hold-011  (KUDA)
sender: Kuda
body:
```
Debit NGN900 to BOLT RIDE on 12-Jul-2026. Bal NGN2100
```
expected: kind=debit amount=900.0 date=2026-07-12T00:00:00.000 counterparty=BOLT RIDE balance=2100.0

# Answer with

The complete contents of agent/out/current/fallback.dart in a single
```dart fenced block. No prose outside the block.
