# Part 1 — The noticing

Status: draft for review
Audience: LinkedIn
Goal: someone reads this and reaches out


## THE POST — copy from here

I kept opening my banking app, staring at the balance, and having no idea where the money had gone.

So I built something to tell me. It has been on the Play Store a while. Last month I sat down with it properly and made a list of everything wrong with it.

Version one was about forty lines that did anything at all: a filter to spot bank messages, and Gemini to read whatever got through.

What it got right:

✅ The data was already there — 5,348 bank texts sitting in my phone, free
✅ No bank logins, no account linking, nothing to connect
✅ It worked. First try.

What it got wrong:

❌ It only ever read today. Skip a day and that day's spending was gone for good. No catching up, no warning.

❌ Gemini was sometimes just wrong. Fuel filed as groceries — and no way to correct it, so a wrong answer stayed wrong forever.

❌ I was throwing away its right answers. My check on its replies accepted one word. Six of my 29 categories have a space in them. So it would correctly say "Public Transport", my own code would reject it, and ask again. Forever.

The AI wasn't the problem. I was.

Part 2: what I built instead, and why the first thing I did was take the AI out. 👇

#BuildInPublic #Fintech #Flutter #Nigeria #ProductDevelopment

## END OF POST


## Media — carousel, three slides, in this order

  ~/Downloads/part1-1.png   how version one worked   (filter -> Gemini -> the app)
  ~/Downloads/part1-2.png   it only ever read today
  ~/Downloads/part1-3.png   it threw away the right answers

  1080 x 1350 each. Post as a multi-image carousel, not one at a time.

  All three carry real screens, and all three are different.
    1  the home screen with spending actually filed against budgets — what
       Gemini's answers turned into
    2  the home screen mid-scan, "Calculating Daily Spend...". That string is
       what confirms these are v1: git log -S puts it in a4e09d1 and removes it
       in e143ded, so it does not exist in the current app.
    3  the add-items screen, word-for-word identical in v1 and today's build,
       so it is honest either way.

  Source: linkedin/slides/ (base.css, s1/s2/s3.html, shots/1-3.png)
  Re-render: linkedin/slides/render.sh s1 s2 s3

Play Store link goes in the FIRST COMMENT, not the post body. A link in the
body suppresses reach.


## Facts used, all verified

  5,348          messages in the inbox dump
  2,406          of them from bank senders
  ~40            lines of real logic in v1
  6 of 29        shipped categories contain a space:
                 Gym Membership, Car Fuel, Mobile Phone,
                 Pet Supplies, Public Transport, Personal Care
  regex          ^\d+(\.\d+)?,\s?\w+$   — \w+ matches no spaces
  retry          do { ... } while (true)  — no limit
  filter         (contains "debit" or "dr") AND (contains "acc" or "acct")
  v1 commit      a4e09d1, February 2025


## Open decisions

1. "my cousin" — keep, or make it generic?
2. Name Gemini, or say "an AI"?
3. Hook is the first two lines. Everything from "Not once" is behind See more.

Decided: the post does not mention how the rebuild was written. The story is
the building process and the decisions in it, not the tooling.

Consequence to plan around: Part 4 was going to be the notification storm that
buried a new user in alerts during onboarding. That story still works — it was
a backfill running per-transaction alerts across thirty days — it just gets
told as a bug that was written, found and fixed, with no note about who typed
it. Nothing in the series depends on the omission being explained.


## Before posting

- Rotate the Gemini API key. It is still live in commit a4e09d1 of a public repo.
- Blur third-party names in every screenshot. Your amounts are yours to publish;
  other people's names are not.
