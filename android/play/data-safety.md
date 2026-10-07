# Data safety form

**Policy → App content → Data safety.** These answers describe what the Android
app sends to the BLML server and to Google Firebase. They match the privacy
policy at https://chat.blml.app/privacy; if the app changes, change both.

## Overview questions

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (TLS to chat.blml.app and to Firebase) |
| Do you provide a way for users to request that their data is deleted? | **Yes** |
| Account creation methods | **Username and password** (with a verified email address) |
| Delete account URL | `https://hungngo.net/blml/delete-account` |
| Can users delete some data without deleting the account? | **Yes**, same URL |

"Collected" means it leaves the phone. "Shared" means given to another company
for its own use. Nothing is shared: the BLML server is yours, and Firebase acts
only as a service provider (crash reports and push delivery), which Google's
form does not count as sharing.

## Data types

For every row: **Collected: Yes · Shared: No · Processed ephemerally: No**.

| Category → type | Required or optional | Purposes to tick | Why |
|---|---|---|---|
| Personal info → **Name** | Required | App functionality, Account management | Display name shown to the people you chat with |
| Personal info → **User IDs** | Required | App functionality, Account management | Username and internal account ID |
| Personal info → **Phone number** | Optional | App functionality, Account management | Lets people who have your number find you |
| Personal info → **Email address** | Required | App functionality, Account management | Asked at sign-up and verified by email; also used for password reset |
| Messages → **Other in-app messages** | Required | App functionality | Chat messages are stored on the server for delivery and history |
| Photos and videos → **Photos** | Optional | App functionality | Photos the user sends, and the profile picture |
| Photos and videos → **Videos** | Optional | App functionality | Videos the user sends |
| Audio files → **Voice or sound recordings** | Optional | App functionality | Voice notes the user records and sends |
| Files and docs → **Files and docs** | Optional | App functionality | Documents the user attaches |
| Contacts → **Contacts** | Optional | App functionality | With permission, phone numbers and emails from the address book are sent to the BLML server to find which contacts are members |
| App info and performance → **Crash logs** | Required | Analytics | Firebase Crashlytics |
| App info and performance → **Diagnostics** | Required | Analytics | Device model and OS version sent with crash reports |
| Device or other IDs → **Device or other IDs** | Required | App functionality | Firebase push token and installation ID, for notifications |

## Not collected

Leave all of these unticked: Location, Financial info, Health and fitness,
Emails or SMS messages, Music files, Calendar, App activity (usage analytics are
switched off), Web browsing, Race, political or religious beliefs, sexual
orientation, and Other info.

Voice and video **calls** are not stored anywhere. They pass between the two
devices, or through the server's relay, only while the call lasts, so they are
not a collected data type.

## Advertising ID

**Policy → App content → Advertising ID:** answer **No**. The app has no ads,
analytics are disabled, and the bundle does not carry the `AD_ID` permission.
