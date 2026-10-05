# Ghost Android Client

Tor-native email client for the [Qompass AI Ghost protocol](../) — anonymous,
Tor-only email on a Ghost onion service.

## What it is

- **Tor bootstrap** with progress UI; a foreground service keeps the onion
  connection alive during mail sync.
- **IMAP (993) + SMTP (465)** through Tor's SOCKS5 proxy. No clearnet
  connection is ever opened; DNS resolves inside Tor.
- **OpenPGP** message encryption via Bouncy Castle (AES-256, integrity packet).
- **Encrypted account storage** (AndroidX Security); Auto Backup disabled.

## What it is not (v1)

- No XMPP chat (the Ghost server also runs Prosody) — roadmap.
- No push notifications — polling only, to stay GMS-free for F-Droid.
- No message reader detail view yet — inbox shows previews.

## Build

Requires Android SDK 35, JDK 17.

```bash
cd android
export ANDROID_HOME=/opt/android-sdk
./gradlew assembleRelease   # AAB/APK, F-Droid builds from source
```

No proprietary dependencies: no GMS, no Firebase. The `tor-android`,
`android-mail`, and Bouncy Castle artifacts are all FOSS.

## Publish

- **F-Droid**: `fastlane/metadata/android/en-US/` carries the listing;
  submit `metadata/ai.qompass.ghost.yml` to fdroiddata per the
  `fdroid-publish` skill workflow.
- **Google Play**: `assembleRelease` produces the AAB; sign with your
  upload key in Play Console. Target SDK 35 meets current Play requirements.

## Layout

```
app/src/main/java/ai/qompass/ghost/
├── MainActivity.kt     # single-activity host, nav flow
├── GhostApp.kt         # application-scoped coroutine scope
├── tor/                # TorManager + TorService (foreground)
├── account/            # AccountStore (encrypted prefs)
├── mail/               # MailClient (IMAP/SMTP over Tor SOCKS)
├── pgp/                # PgpManager (Bouncy Castle)
└── ui/                 # Compose screens + theme
```
