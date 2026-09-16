# Part 3 — Letting the app say what it knows

Status: draft for review
Follows: Part 2, which ended on "even something this robust still had severe limitations"
Screenshot state: story branch, day = 1 for the flaw, day = 2 for the fix


## THE POST — copy from here

My app groups a year of spending by who you paid. So instead of 1,271 questions, you get 20.

Twenty is better. Twenty was still a chore.

Every one of them went like this:

❌ Tap a name
❌ Read the four budgets you keep
❌ Scroll past twenty-five you don't
❌ Pick one
❌ Then make up a monthly budget for it, starting from zero

Five steps, twenty times.

And the app already knew the answers. It had 38 payments to that one kitchen sitting right there. It just never said anything.

So I made it talk:

✅ It tells you what it thinks, in plain words — "Bolt Ride is a transport merchant"
✅ Anything it is sure about is already filed when you open the screen
✅ For a budget you don't have yet, it offers one. Tap it and the app creates it
✅ It suggests the amount too, from what you actually spend

One tap instead of five.

And it spreads, which is the point. The moment "Lunch" existed, every restaurant the app recognised filed itself there. Two were done before I made a second choice.

Same app. It just stopped keeping what it knew to itself.

Part 4 👇

#BuildInPublic #Fintech #Flutter #Nigeria #ProductDevelopment

## END OF POST


## Media — carousel, three slides, in this order

  ~/Downloads/part3-1.png   the old way, end to end   (day 1)
  ~/Downloads/part3-2.png   twenty questions, one hundred decisions
  ~/Downloads/part3-3.png   the new way, end to end   (day 2)

  1080 x 1350 each. 1 and 3 are three-phone sequences and deliberately mirror
  each other: same screen, same order, five steps against one.

  Every phone is a real screenshot off the device, demo data, captured over
  adb. Nothing is mocked.

    part3-1  bare list ("Nothing tagged yet") -> bare picker for MAMA NKECHI
             KITCHEN, 38 transactions -> "Set a budget for Lunch" at ₦0 with
             Start tracking greyed out
    part3-3  ghost chips with reasons -> "Set a budget for Transport" pre-filled
             at ₦24,000 -> Chowdeck and The Place auto-filed into Lunch,
             "2 of 8 tagged"

  part3-2 was originally a redundancy slide (the same name 51 times, 1,271
  payments, 63 min vs 60 sec). That argues PART TWO's point — grouping — not
  Part 3's, so it was replaced. The original is kept at
  linkedin/slides/p3b-old-part2.html if it is ever wanted as a fourth image
  for Part 2; note it overlaps part2-1, which already makes the 1,271 -> 20
  case with the real screen.

  Source: linkedin/slides/ (base.css, p3a/p3b/p3c.html)
  Re-render: linkedin/slides/render.sh p3a p3b p3c

Play Store link in the FIRST COMMENT, not the body.


## Facts used, all verified

  1,271      payments found by the parser (measured, from Part 2)
  20         maximum questions — batchTagCandidates takes `limit = 20`
  29         options in the day-1 picker: 4 tracked + 25 in the catalogue
  38         transactions to Mama Nkechi Kitchen, demo data
  45         to Bolt Ride, demo data
  ₦24,000    the budget the day-2 app proposed for Transport, from spending
  ₦0         where the day-1 budget sheet starts, button disabled
  2 of 8     tagged automatically after one category was created

  100 on part3-2 is 20 names x 5 steps, both counted from the day-one build:
  tap, read the tracked chips, scroll the catalogue, pick, set a budget.

  Real reason strings captured, usable as quotes:
    "Bolt Ride is a transport merchant."
    "The name suggests Food, which you are not tracking yet."
    "Money sent to a person, not a purchase. Pick where it belongs."


## What is gated where, for later parts

  Story.suggestions (day >= 2) gates BOTH the inline ghost chips and
  _autoAssign, which returns 0 at day 1 — so at day 1 `_guesses` stays empty
  and the picker's "THE APP SUGGESTS" section does not render at all. That is
  why the day-1 picker is a bare catalogue.

  Story.budgetsFromHistory (day >= 6) is what pre-fills the budget sheet. At
  day 1 it opens at ₦0; at day 2 the ₦24,000 came from the history path being
  reachable through the ghost-chip route.


## Note on the device

  The app installed on the phone is a DEBUG build, signed with the debug
  keystore. A release build will not install over it (signature mismatch).
  Build with `flutter build apk --debug` and `adb install -r` to upgrade in
  place without losing the login.
