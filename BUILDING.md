# Building the BLML apps

What had to be installed and fixed to get the Android and iOS clients compiling on this
machine, so the next person (or the next machine) doesn't rediscover it.

## Toolchain

Nothing Android-related was installed before this; Xcode was already present.

```bash
brew install openjdk@17 cocoapods
brew install --cask android-commandlinetools
```

Then the SDK packages:

```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.20/libexec/openjdk.jdk/Contents/Home
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

Xcode 26.6 was already installed. Set both env vars in your shell profile so you don't
have to repeat them.

## Local config files (all gitignored upstream)

These are expected to be supplied per-developer and the build **fails at configure time**
without them. Created here as placeholders:

| File | Purpose | Status |
|---|---|---|
| `android/local.properties` | points Gradle at the SDK | real |
| `android/keystore.properties` | release signing | **dev key — replace before publishing** |
| `android/blml-release.keystore` | the key itself, password `blmldev` | **dev key** |
| `android/app/google-services.json` | Firebase config | **placeholder — push won't work** |
| `ios/GoogleService-Info.plist` | Firebase config | **placeholder — push won't work** |

Note the iOS plist goes at the **repo root** (`ios/GoogleService-Info.plist`), not in
`ios/Tinodios/`. Putting it in the `Tinodios/` folder gives you
`error: Build input file cannot be found`, plus two confusing cascading `__preview.dylib`
link failures that have nothing to do with the real problem.

To make push actually work: create a Firebase project, register an Android app with
package `app.blml.chat` and an iOS app with bundle id `app.blml.chat`, download the real
config files, replace both placeholders, and put the matching server key into
`server/server/tinode.conf`.

## Upstream bug that had to be patched

`android/gradle.properties` shipped with:

```
org.gradle.jvmargs=-Xmx4096m -XX:MaxPermSize=1024m ...
```

`MaxPermSize` was removed in Java 8. On JDK 17 the Gradle daemon refuses to start at all
("Unrecognized VM option 'MaxPermSize=1024m'"). The flag is simply deleted — the
permanent generation it referred to hasn't existed for a decade.

## Build commands

**Android debug APK** (~3.5 min cold):

```bash
cd android && ./gradlew :app:assembleDebug
```

Output: `android/app/build/outputs/apk/debug/app-debug.apk`

**Android release APK** — signs with the dev keystore above:

```bash
cd android && ./gradlew :app:assembleRelease
```

**iOS simulator build**:

```bash
cd ios && xcodebuild -workspace Tinodios.xcworkspace -scheme Tinodios \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 EXCLUDED_ARCHS=x86_64 build
```

Run `pod install` first if `ios/Pods/` is missing. `CODE_SIGNING_ALLOWED=NO` is what lets
this build without an Apple Developer account — it is fine for the simulator but you
cannot install the result on a real device. For a device build or TestFlight you need the
$99/year membership and a provisioning profile for `app.blml.chat`.

`ARCHS=arm64 EXCLUDED_ARCHS=x86_64` is required on Apple Silicon. WebRTC-lib and
MobileVLCKit ship arm64-only simulator slices, so the default "build every architecture"
behaviour fails at link time with `ld: symbol(s) not found for architecture x86_64` in
`CallViewController.o`. The arm64 slice — the one an Apple Silicon simulator actually
runs — is fine. This only affects Intel Macs, which would need different pod versions.

### The build that runs, vs. the build that only compiles

`CODE_SIGNING_ALLOWED=NO` compiles fine but produces an app that **crashes on launch**:

```
TinodiosDB/BaseDb.swift:73: Fatal error: Unexpectedly found nil while unwrapping an Optional
```

The app keeps its SQLite database in an App Group container
(`group.co.tinode.tinodios.db`, declared in `Tinodios/Tinodios.entitlements` and shared
with the notification extension). Disabling code signing means entitlements are never
embedded, so `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil and
`BaseDb.init` force-unwraps it.

To get a build that actually **runs** on the simulator, sign ad-hoc instead:

```bash
cd ios && xcodebuild -workspace Tinodios.xcworkspace -scheme Tinodios \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build ARCHS=arm64 EXCLUDED_ARCHS=x86_64 \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

Note the app group keeps the **original** `co.tinode.tinodios.db` name even after
rebranding, because the `TinodiosDB` framework's bundle id is deliberately left alone
(see REBRANDING.md). The entitlement and `BaseDb.kAppGroupId` agree, so this is correct —
do not "fix" one without the other.

Beware: piping xcodebuild through `tail` masks its exit code, so a failed build looks like
it succeeded. Redirect to a log file and check `$?` instead.

## Server addresses baked into the builds

| Build | Server |
|---|---|
| Android debug | `sandbox.tinode.co` — Tinode's public sandbox, so the debug APK is testable before your server exists |
| Android release | `chat.blml.app` |
| iOS Debug | `127.0.0.1:6060` (from `devel.xcconfig`) |
| iOS Release | `chat.blml.app` (from `prod.xcconfig`) |

Both apps let the user override the server address in settings, so these are defaults,
not hard limits. Change them in `android/app/build.gradle` (the `resValue` lines) and the
two `.xcconfig` files.

## Android versioning after the monorepo flatten

`android/build.gradle` used to derive its version from `git rev-list --count` and
`git describe --tags`. Flattening the four upstream clones into one repo removed
the version tags, so `git describe` returned "" and `.substring(1)` threw
`begin 1, end 0, length 0` — the build failed during configuration, before
compiling anything.

Both functions now return static values:

```groovy
static def gitVersionCode() { return 1 }
static def gitVersionName() { return "1.0.0" }
```

**Bump `gitVersionCode` for every Play Store upload** — Google requires it to
strictly increase, and nothing does it automatically now.
