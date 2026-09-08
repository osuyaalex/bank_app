# Deploying to bank-ai.netlify.app

Two files at the site's publish root, then redeploy.

## `index.html`

Replaces the Google OAuth2 disclosure page currently at the site root.

That page says BankAL requests Google's `gmail.readonly` scope and "filters
emails for financial keywords". None of it is true any more, and it is not
partly true either: the app has no `google_sign_in` dependency, requests no
Google scopes, and signs users in with an email address and a password.
`lib/google_auth_client.dart` was the last trace of it and has been deleted.

A live page claiming an app reads your email when it does not is worse than no
page at all. This replaces it with what is actually the case, tells anyone who
granted the old permission how to withdraw it, and points at the privacy policy
for everything else.

**Do not simply delete the site.** If a Google Cloud OAuth client still exists
for this project, its consent screen links here.

## `_redirects`

Forwards the old privacy policy URL to the one served from the app's own
repository. `/policy` only -- the root is the page above.

## Then, in Google Cloud

If the OAuth client for this project is no longer used, remove it. An unused
client with a restricted scope attached is a standing liability and something
to answer for at every review.

If it is still needed, point its privacy policy link at
`https://osuyaalex.github.io/bank_app/policy/` and drop `gmail.readonly` from
the consent screen.
