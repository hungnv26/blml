# Google Play release kit

Everything needed to put BLML on Google Play, prepared ahead of the developer
account being verified.

| File | What it is |
|---|---|
| [store-listing.md](store-listing.md) | App name, descriptions (English and Vietnamese), category, contact details |
| [data-safety.md](data-safety.md) | Answers for the Data safety form |
| [app-content.md](app-content.md) | App access, content rating, target audience, permission declarations |
| `graphics/` | Icon, feature graphic and phone screenshots (`make-graphics.py` rebuilds them) |

## Build the bundle

Play takes an Android App Bundle, not an APK.

```bash
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew bundleRelease
```

Output: `android/app/build/outputs/bundle/release/app-release.aab`, signed with
`blml-release.jks`. Raise `gitVersionCode()` in `android/build.gradle` for every
upload; Play refuses a version code it has seen before.

## Steps in Play Console

1. **Create app.** Name `BLML: Private Family Chat`, default language English,
   type App, Free.
2. **App signing — do this before the first upload.** In the first release
   screen choose **Use a different key → Export and upload a key from Java
   keystore**, and upload the existing key with Google's PEPK tool:

   ```bash
   java -jar pepk.jar --keystore=android/blml-release.jks --alias=<key alias> \
     --output=blml-play-key.zip --include-cert --rsa-aes-encryption \
     --encryption-key-path=<encryption_public_key.pem from the console>
   ```

   Play then signs with the same key as the APK on chat.blml.app/android, so the
   Play version installs as an update over it. If Google generates a new key
   instead, everyone must uninstall the APK first and loses their local data.
   This choice cannot be changed later.
3. **Store listing:** paste from store-listing.md and upload `graphics/`.
4. **App content:** work through app-content.md and data-safety.md.
5. **Closed testing:** create a track, upload the `.aab`, add at least 12
   testers by Google account, and share the opt-in link. They must stay opted in
   for 14 days before production access can be requested.
6. **Production:** apply for access, answer the questions about the test, and
   release.

## What was changed in the app for Play

- Removed permissions nothing used: full photo and video library access (the
  app already used the system photo picker), the advertising ID, legacy account
  permissions, answering phone calls, disabling the keyguard and installing
  shortcuts.
- Account deletion page outside the app: https://hungngo.net/blml/delete-account
