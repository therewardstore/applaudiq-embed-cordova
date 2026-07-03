# @applaudiq/embed-cordova

[![npm](https://img.shields.io/npm/v/@applaudiq/embed-cordova.svg)](https://www.npmjs.com/package/@applaudiq/embed-cordova)

Embed the full **Applaud IQ** recognition portal inside a **Cordova / PhoneGap** app — plain Cordova or
**legacy Ionic React / Angular / Vue on Cordova** — with **auto-login** (a one-time token minted by your server)
or **manual login** (the portal's own email / SSO). The portal renders in an `<iframe>`; **SSO** and the
Android **Back** button go through Cordova's native plugins.

- Behavioral **parity with `@applaudiq/embed-capacitor`** — same `ApplaudIQ.init().open()` API, the same iframe +
  postMessage bridge, the same SSO + Back flow. Only the native layer differs (Cordova plugins).
- **Auto + manual login**, the **HR-approval gate**, and native **SSO** (Google / Microsoft).
- Required Cordova plugins: `cordova-plugin-inappbrowser`, `cordova-plugin-customurlscheme`.

> **New app?** Use [`@applaudiq/embed-capacitor`](https://www.npmjs.com/package/@applaudiq/embed-capacitor) —
> Capacitor is the modern successor to Cordova (and the path for new Ionic apps). This package exists for
> **existing** Cordova / PhoneGap / legacy-Ionic-Cordova apps.

---

## 1. Install

```bash
npm install @applaudiq/embed-cordova@^1.3.0
cordova plugin add cordova-plugin-inappbrowser cordova-plugin-customurlscheme
```

`cordova-plugin-inappbrowser` opens SSO in the system browser; `cordova-plugin-customurlscheme` delivers the SSO
callback deep link to `window.handleOpenURL`. (`backbutton` + `deviceready` are Cordova core — no extra plugin.)

## 2. Register your SSO callback scheme

SSO opens in the system browser and the backend hands the one-time code back to **your app's** deep link. Pick a
scheme **unique to your app** (not the brand-wide `applaudiq://`) and declare it in **`config.xml`** — Cordova
generates the native iOS `CFBundleURLSchemes` + Android intent-filter from it:

```xml
<!-- config.xml -->
<!-- cordova-plugin-customurlscheme registers the scheme on both platforms -->
<plugin name="cordova-plugin-customurlscheme" spec="^5.0.2">
  <variable name="URL_SCHEME" value="myapp" />
</plugin>
```

Pass it as `ssoCallback` (the SDK sends it to the backend as `native_redirect`). Default `applaudiq://sso-callback`.

## 3. Render the embed

**Manual login** — just the publishable key:

```ts
import { ApplaudIQ } from '@applaudiq/embed-cordova';

ApplaudIQ.init({ key: 'pk_live_…', ssoCallback: 'myapp://sso-callback' })
  .open({ mode: 'manual', render: 'fullscreen' });
```

**Auto-login** — a one-time token your backend minted (`POST /api/v1/embed/sessions`):

```ts
const embed = ApplaudIQ.init({ key: 'pk_live_…', ssoCallback: 'myapp://sso-callback' }).open({
  mode: 'auto',
  token: embedToken,
  render: 'fullscreen',
  onReady: () => {},        // signed in
  onAuthPending: () => {},  // awaiting HR approval
  onError: (m) => {},       // failed (incl. SSO ?error=)
  onClose: () => {},        // dismissed
});
// later: embed.close();
```

> Call `open()` after Cordova's `deviceready` event (so the plugins are loaded) — typically from a button tap,
> which always fires after launch.

## 4. Options

| Option | |
|---|---|
| `config.key` | Publishable key (`pk_live_…`). Required, both modes. |
| `config.baseUrl` | Portal origin. Defaults to the production portal. **HTTPS** in production. |
| `config.ssoCallback` | Your app's `scheme://host` deep link (default `applaudiq://sso-callback`); sent as `native_redirect`. |
| `config.backNavigation` | `true` (default): **Android** hardware Back + **iOS** left-edge swipe step back inside the embed (`onClose` at the root). `false`: platform default, no iOS swipe. See [Back navigation](#back-navigation). |
| `mode` | `'auto'` (needs `token`) or `'manual'` (portal login). |
| `render` | `'fullscreen'` (default) · `'modal'` · `'inline'` (needs `container`). |
| callbacks | `onReady` · `onAuthPending` · `onError(message)` · `onClose` · `onSignOut`. |

## Back navigation

The portal renders in a **cross-origin iframe**, so the SDK can't read its history directly. With
`backNavigation` on (the default), it relays a back request to the portal, which steps back through its own
screens and replies only when it's already at the embed root — then the SDK tears the embed down and fires
`onClose`. Route home in `onClose`:

- **Android** — the hardware Back button (Cordova's `backbutton` event).
- **iOS** — a **left-edge swipe** (iOS has no hardware Back, and the WebView's own swipe-back can't traverse the
  iframe). The gesture lives in the leftmost ~20px of the embed.

```ts
.open({
  mode: 'manual',
  onClose: () => { location.hash = '#/'; },   // dismissed at the embed root → go Home
});
```

## How SSO works

`mode: 'manual'` shows the portal's email / SSO login inside the embed. SSO can't run in a WebView, so the SDK
opens the IdP in the **system browser** (`cordova-plugin-inappbrowser` `open(url, '_system')`) at
`…/auth/sso/{provider}/employee/authorize?native=1&native_redirect=<ssoCallback>`. The backend redirects the
one-time code to `<ssoCallback>?code=` (or `?error=`), `cordova-plugin-customurlscheme`'s `window.handleOpenURL`
catches it, and the SDK relays it into the embed, which redeems it and reloads — signed in.

## Downloads & external links

When the portal (or the reward store nested inside it) needs to open a URL outside the WebView —
a file download, a payment page, or an OAuth handoff — it sends the `applaudiq:open-external` bridge
message with payload `{ url }`. The SDK opens `http(s)` URLs in the **system browser**
(`cordova-plugin-inappbrowser` `open(url, '_system')`). No app code is required.

The reward store's **gift-card voucher download** additionally sends `applaudiq:save-file` with
`{ base64, filename, mime }`. To enable it, add the two **optional** plugins to your app:

```bash
cordova plugin add cordova-plugin-file cordova-plugin-x-socialsharing
```

The SDK writes the file to the app cache and opens the OS share sheet. Without these plugins, voucher
downloads are a silent no-op.

## Test integration

A runnable example ships for each framework in
[`applaudiq-sdk-example`](https://github.com/therewardstore/applaudiq-sdk-example) under
`native-integration/cordova/` (vanilla · react · angular · vue · ionic-react · ionic-angular · ionic-vue).

Latest: **v1.3.0 (LTS)**. See [CHANGELOG.md](./CHANGELOG.md). MIT licensed.
