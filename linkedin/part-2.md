# Part 2 — Taking the AI out

Status: draft for review
Follows: Part 1, which ended on "why the first thing I did was take the AI out"
Screenshot state: story branch, day = 1


## THE POST — copy from here

I took the AI out of my budgeting app.

Then I measured what it cost me. It cost me nothing.

I ran both versions over the same 5,348 messages from my own phone. On the one job the app exists to do — catching money leaving your account:

🤖 With Gemini: 1,270 transactions
⚙️ Without it: 1,271

A dead heat. The model I had been paying for, waiting on, and blaming for wrong answers was not doing the work I thought it was doing.

So why take it out at all?

❌ It sent every one of your bank alerts to Google
❌ It cost money per user, per transaction, forever
❌ It needed a connection to tell you what you spent on lunch
❌ When it got something wrong, there was no way to tell it so

What replaced it is a parser. It reads the message on your phone, and nothing leaves the phone.

✅ Taught on 2,406 real bank messages
✅ Reads 25 different ways of writing a date, because Nigerian banks could not agree on one
✅ Last week a UBA user told me it was working. I have never held a UBA account or seen their alerts

And it buys you the thing that actually matters: you stop sorting your own spending. The app groups a year of payments by who you paid, and asks about each name once.

1,271 payments. 20 questions.

But even something this robust still had severe limitations.

Part 3 👇

#BuildInPublic #Fintech #Flutter #Nigeria #ProductDevelopment

## END OF POST


## Media — carousel, three slides, in this order

  ~/Downloads/part2-1.png   the batch screen — 1,271 payments, 20 questions
  ~/Downloads/part2-2.png   1,270 vs 1,271, the dead heat
  ~/Downloads/part2-3.png   three banks, one payment, three formats

  1080 x 1350 each. Post as a multi-image carousel.

  part2-1 carries the real batch screen, captured over adb from the story
  branch at day = 1. The names on it are demo data, so no real person appears.
  The slide says so in the footer.

  "20 questions" is exact, not rounded: batchTagCandidates in
  lib/data/migration_plan.dart takes `limit = 20`. The screen never shows more.

  part2-2 deliberately uses no chart. Two numbers that are nearly identical is
  the whole point, and a bar chart makes them look the same by accident rather
  than on purpose.

  Counterparties appear here only at surface level — "it groups by who you
  paid". How they are actually built (truncated spellings, aliases,
  canonicalisation) is held back for Part 3.

  Source: linkedin/slides/ (base.css, p2a/p2b/p2c.html, shots/batch.png)
  Re-render: linkedin/slides/render.sh p2a p2b p2c

Play Store link in the FIRST COMMENT, not the body.


## Facts used, all verified

  5,348          messages in the inbox dump
  2,406          from bank senders
  1,717 / 2,376  total recognised, old filter vs new parser
  1,270 / 1,271  money going out — the dead heat
  432 / 435      bank charges
  13 / 670       money coming in (v1 was debit-only by design)
  2              junk items v1 let through that v2 rejected:
                 a Wema card-renewal advert, and a scam text
  25             date formats handled
  UBA            reported working by a user, on a bank not in the test data

  IMPORTANT: the 1,270/1,271 comparison is v1 against the FINISHED parser,
  not the first draft that only knew Zenith and Wema. If challenged, say
  "the parser I ended up with". The distinction is the honest one.


## Open decisions

1. "your sister" in the batch screen paragraph — keep, or make it generic?
2. Name Gemini again, or just "the AI" now that Part 1 named it?
3. "Six hundred questions became twenty" — check this against your real
   numbers before posting. Use your actual figures if they are to hand.


## Cliffhanger

Ends on "but even something this robust still had severe limitations".
Part 3 pays that off: the batch screen looked finished and still confused
people, because they arrived at it with nothing to sort into.
