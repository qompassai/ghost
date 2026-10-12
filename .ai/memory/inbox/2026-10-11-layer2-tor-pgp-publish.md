# 2026-10-11 — Layer 2 landed: Tor bridge wired, PGP compose end to end, publish prep

Overnight campaign pass (authorized by Matt 2026-10-11 23:46 PDT).

## Tor (Layer 2)

- `TorAndroidBridge` TODOs implemented in `tor/TorManager.kt` against the
  real tor-android 0.4.9.6 API (verified from the AAR + bytecode, not docs):
  provider `org.torproject.jni.TorService` is intent-driven
  (ACTION_START/STOP), publishes status over LocalBroadcastManager
  (ACTION_STATUS), and reports bootstrap percent via the bound service
  `getInfo("status/bootstrap-phase")`. Bridge start blocks (bounded
  100 s, below TorManager's 120 s) pumping progress; stop interrupts the
  wait, unbinds, and stops both services. LocalBroadcastManager is
  deprecated generally but is the provider's only status channel —
  file-level suppression with rationale in TorManager.kt.
- `tor/TorService.kt` is now a real foreground anchor: startForeground in
  onStartCommand, forwards ACTION_START to the provider, ACTION_STOP on
  destroy, START_NOT_STICKY (never resurrect the tunnel silently).
- build.gradle.kts: explicit localbroadcastmanager 1.1.0 dep (used
  directly now; was transitive via tor-android).

## OpenPGP compose (Layer 2)

- New `pgp/RecipientKeyStore.kt`: recipient public keys in
  EncryptedSharedPreferences, normalized addresses, 64 KiB armor bound.
- `ui/ComposeScreen.kt`: recipient-key picker/import (paste armor →
  PgpManager.loadPublicKey validates → stored). Send is enabled only
  with a validated key for the exact recipient; the body is encrypted
  with PgpManager.encryptFor and onSend receives armor only. The v1
  plaintext send path is gone.
- 5 new JVM tests for address normalization (18/18 total, was 13/13).

## Publish prep (Layer 3, in-repo only)

- targetSdk 35 → 36 (compileSdk already 36).
- `android/fdroid-recipe.draft.yml`: fdroiddata-format draft; gaps are
  screenshots, a release tag, and the submission itself (Matt's steps).
- `scripts/publish/keystore.sh` (Tiger Style bash, shellcheck/shfmt
  clean): generates the Play signing keystore into
  $XDG_DATA_HOME/keystores/ghost/ (dir created on primo, mode 700).
  Dry-run executed and recorded 2026-10-11; the real run is Matt's —
  agents do not mint signing keys.

## Gates (primo, 2026-10-11 night)

- `./gradlew assembleDebug testDebugUnitTest`: BUILD SUCCESSFUL,
  zero Kotlin warnings, tests 18/18 (MessageBodyExtractor 11,
  ReaderDecryptFlow 2, RecipientKeyStore 5). Debug APK 52,000,782 B.
- No PHP files changed this pass (php -l not applicable).
- SCIP: scip-java is installed and ran, but produced no shards — the
  Android tree is pure Kotlin and scip-java indexes Java sources only.
  No scip-php exists on primo. Recorded as attempted/not possible.
- NOT verified: on-device Tor bootstrap + mail flow (no device step in
  this pass; Layer 3 real-device verification remains).
