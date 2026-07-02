# Changelog

All notable changes to `@applaudiq/embed-cordova` are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

_Nothing yet._

## [1.2.0] — LTS

**Reward-store downloads / external links.** The SDK now handles the `applaudiq:open-external` bridge message
(payload `{ url }`) and opens the URL in the device's system browser — used by the embedded portal for file
downloads, payment pages, and OAuth handoffs. Backward-compatible; no changes to the public API surface.

## [1.1.1] — LTS

**First release of the Cordova SDK.** Joins the unified **1.1.1 LTS** Applaud IQ embed-SDK family (Web · iOS ·
Android · React Native · Flutter · Capacitor · Cordova). Behavioral parity with
[`@applaudiq/embed-capacitor`](https://www.npmjs.com/package/@applaudiq/embed-capacitor): the same
`ApplaudIQ.init().open()` API, the same `<iframe>` (`/embed`) + postMessage bridge, the same auto / manual login,
HR-approval gate, native SSO (system browser + deep-link return), and Back navigation (Android hardware Back + iOS
left-edge swipe). The only difference is the native layer:

- SSO opens in the system browser via `cordova-plugin-inappbrowser` (`open(url, '_system')`).
- The SSO callback deep link returns via `cordova-plugin-customurlscheme` (`window.handleOpenURL`).
- Android hardware Back uses the Cordova `backbutton` event.

For **new** apps, prefer `@applaudiq/embed-capacitor` — this package targets existing Cordova / PhoneGap /
legacy-Ionic-Cordova apps.
