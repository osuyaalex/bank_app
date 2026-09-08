# Privacy policy: what has to change

The policy at <https://bank-ai.netlify.app/policy> currently promises that SMS
content never leaves the device. The format-report feature breaks that promise
unless the promise is narrowed, so this has to go live **before** the feature
does.

Its source is not in this repository. Everything below is ready to paste.

---

## 1. The sentence that is now untrue

**Current:**

> SMS messages are processed locally on your device and are not stored.

**Replace with:**

> SMS messages are read and processed entirely on your device. Their contents
> are never uploaded, with one exception that only happens if you ask for it:
> if BankAL cannot understand your bank's alerts, you can offer to send us the
> *layout* of one, with every digit and every name removed on your device
> first. That is described under "Reporting a bank we cannot read" below.

**Current:**

> raw SMS messages never persist

**Replace with:**

> Raw SMS messages are never stored or transmitted. Only processed transaction
> summaries are retained, and , where you have explicitly chosen to send one ,
> the redacted layout of an unreadable alert.

---

## 2. New section

Paste this after "SMS Access & Data Collection".

> ### Reporting a bank we cannot read
>
> BankAL can only read a bank's alerts once it has been taught that bank's
> format. If yours is one it does not recognise, the app will offer to send us
> the **shape** of one of those messages so we can add support for it.
>
> **This is optional.** Nothing is sent unless you tap "Send this", and you can
> use the app whether you help or not.
>
> **We show you exactly what would be sent, before you decide.** Every digit is
> replaced with `#` and every word that is not standard banking vocabulary is
> replaced with a placeholder, on your device, before anything is transmitted.
> A message like:
>
> ```
> Acct:2211234558
> DT:23/08/2026 09:06:35 PM
> NIP CR/MOB/ABUBAKAR ALIYU/PAL
> DR Amt:300.00
> Bal:142.92
> ```
>
> is sent to us as:
>
> ```
> Acct:##########
> DT:##/##/#### ##:##:## PM
> NIP CR/MOB/<name> <name>/<w>
> DR Amt:###.##
> Bal:###.##
> ```
>
> **What we receive:** the redacted layout above; the sender ID the message came
> from, which tells us the bank's name; your account identifier, so we can reach
> you if we fix it; the app version; and the time you sent it.
>
> **What we do not receive:** the message itself, the amount, your balance, your
> account number, or the name of anyone you paid. None of those leave your
> phone.
>
> **Your email, only if you offer it.** After a report is sent, we ask
> separately whether you would like to be told when your bank is supported. It
> is optional, it is used for that and nothing else, and we do not add you to
> any mailing list.
>
> **How long we keep it.** A report is kept until the format it describes is
> supported, and for up to twelve months after that so we can check the fix
> still holds. Email addresses are deleted once we have written to you, or
> immediately on request.
>
> **Withdrawing it.** Email us and we will delete any report linked to your
> account. Because reports carry your account identifier, we can find them.

---

## 3. Retention section

Add:

> Format reports are kept until the bank format they describe is supported, and
> for up to twelve months afterwards. Email addresses given with a report are
> deleted once we have used them.

---

## 4. Data sharing section

The existing wording already covers Firebase Firestore as the storage
processor, and format reports are stored there like everything else, so no
change is strictly required. If you want to be explicit, add:

> Format reports are stored in Firebase Firestore (Google LLC) alongside our
> other data. They are not shared with anyone else, and they are never sold.

---

## 5. Play Console: Data Safety

Update the form to match. The relevant answers:

| Question | Answer |
|---|---|
| Does your app collect or share SMS data? | **Yes** |
| Is it collected or shared? | **Collected** (we do not share it onward) |
| Is it optional or required? | **Optional** , the user chooses per report |
| Purpose | **App functionality** , adding support for their bank |
| Is it encrypted in transit? | **Yes** |
| Can users request deletion? | **Yes** |

Declare **Email address** too, as optional, purpose *App functionality* , you
use it to tell them when their bank works.

The important nuance: what is collected is *derived from* SMS but is not the
message. Say so in the free-text field rather than leaving a reviewer to guess:

> Users may optionally send the redacted layout of a bank alert our parser
> cannot read. All digits and names are removed on the device before
> transmission; the message body is never sent.

---

## 6. Do not weaken the in-app disclosure

The sheet that shows the user their exact redacted payload before asking is
what makes the consent real, and it is also the "prominent disclosure" Play
requires for this kind of collection. If it is ever replaced with a summary of
what would be sent rather than the thing itself, both the consent and the
compliance argument get considerably weaker.
