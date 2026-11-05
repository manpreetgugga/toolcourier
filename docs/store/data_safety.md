# Data safety answers

Play Console → **App content → Data safety**, for 1.1.0 and on: what
AdMob and Firebase (Google Analytics and Crashlytics, see README's
Statistics section) collect. 1.0.0's form said the app collects no data.
The answers must match the [privacy policy](../../PRIVACY.md), which must
be on `main` before the release goes out.

## Data collection and security

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes (AdMob and Firebase send everything over HTTPS) |
| Which methods of account creation does your app support? | None: the app has no accounts |
| Do you provide a way for users to request that their data is deleted? | No (there is no account to tie it to; Settings → Statistics stops collection, and uninstalling resets the IDs) |

## Data types

Nothing is **shared** by the developer: Google runs AdMob and Firebase as
service providers. Nothing is processed ephemerally. Where AdMob collects
a type whatever the player does, it is **required**; what only Firebase
collects is **optional**, since Settings → Statistics turns it off.

| Data type | Collected by | Required or optional | Purposes |
| --- | --- | --- | --- |
| Location → Approximate location | AdMob (IP address); Analytics (country and region from the IP address) | Required | Advertising or marketing, Analytics, Fraud prevention, security and compliance |
| App activity → App interactions | AdMob (ads seen and tapped); Analytics (levels, moves, hints, screens, reminders opened) | Required | Advertising or marketing, Analytics |
| App info and performance → Crash logs | Crashlytics; AdMob | Required | Analytics |
| App info and performance → Diagnostics | Crashlytics (memory, storage, errors); AdMob (ad performance) | Required | Analytics |
| Device or other IDs | AdMob (advertising ID, app set ID); Analytics (app instance ID, the advertising ID outside the EEA, UK and Switzerland); Crashlytics (installation ID) | Required | Advertising or marketing, Analytics, Fraud prevention, security and compliance |

Leave everything else unticked: no personal info, financial info, health,
messages, photos, audio, files, calendar, contacts, web browsing or
precise location.

## Also in Play Console

- **App content → Ads**: still "Yes, my app contains ads".
- **App content → Advertising ID**: still "Yes", with **Analytics**,
  **Advertising or marketing** and **Fraud prevention, security and
  compliance** ticked (already so since 1.0.0).
- **Privacy policy**: unchanged address,
  `https://github.com/manpreetgugga/toolcourier/blob/main/PRIVACY.md`.
