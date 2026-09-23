# Scoffie iOS

SwiftUI client for Scoffie. The app covers recipes, weekly planning, calendar view, shopping list flows, household collaboration, realtime sync, and local notification handling.

## Requirements

- Xcode 17+
- iOS Simulator or physical iPhone
- Running backend API

## Open and build

Open:

- [`Scoffie.xcodeproj`](./Scoffie.xcodeproj)

CLI build:

```bash
xcodebuild -project "Scoffie.xcodeproj" -scheme "Scoffie" -destination "generic/platform=iOS Simulator" build CODE_SIGNING_ALLOWED=NO
```

## Backend configuration

The app resolves `API_BASE_URL` in this order:

1. process environment
2. Info.plist / build setting
3. built-in production fallback

Checked-in defaults stay on production.

During `Debug` builds, a build phase rewrites the built app's `Info.plist` like this:

- branch `master` or `main`: `https://api.scoffie.app`
- any other local branch: `http://localhost:3000`

`Release` builds always use `https://api.scoffie.app`.

For local backend development on a physical iPhone, override `API_BASE_URL` in your local Xcode scheme or launch environment and use your Mac's LAN IP (for example `http://192.168.x.x:3000`) rather than `localhost`, which resolves to the phone itself.

## Runtime notes

- URL scheme: `scoffie://`
- Bundle identifier: `app.scoffie.ios`
- Push token registration happens automatically after app launch and login
- APNs testing requires a physical iPhone

## Current auth note

The current app build uses Sign in with Apple and posts the resulting token to `POST /auth/apple`.

## CI and TestFlight

Builds, signing and TestFlight uploads run in **Xcode Cloud** (included with the Apple Developer Program). Since 23.09.2026 GitHub Actions no longer runs macOS jobs: a macOS minute counts ten times against the Actions quota, and those jobs used it up.

- [`ios-ci.yml`](./.github/workflows/ios-ci.yml): secret scanning (gitleaks) on Linux only
- [`ci_scripts/ci_post_xcodebuild.sh`](./ci_scripts/ci_post_xcodebuild.sh): after an Xcode Cloud archive, uploads dSYMs to Sentry. It needs a `SENTRY_AUTH_TOKEN` secret in the Xcode Cloud workflow, and never fails the build.

Release versioning policy:

- `MARKETING_VERSION` is manual and should be bumped only when starting a new release line, for example `1.0` -> `1.1`
- `CURRENT_PROJECT_VERSION` is set by Xcode Cloud (its build number)

## Related backend docs

- [Backend README](../scoffie-backend/README.md)
- [`APNS_SETUP.md`](../scoffie-backend/APNS_SETUP.md)
- [`DEPLOYMENT.md`](../scoffie-backend/DEPLOYMENT.md)
