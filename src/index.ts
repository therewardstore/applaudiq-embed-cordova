/**
 * @applaudiq/embed-cordova — renders the full Applaud IQ recognition portal inside a
 * Cordova / PhoneGap / legacy-Ionic-Cordova app (an `<iframe>` to `<baseUrl>/embed`) with
 * auto / manual login + native SSO. Behavioral parity with the Capacitor SDK — same
 * `ApplaudIQ.init().open()` API, the same iframe + postMessage bridge, the same SSO + Back
 * flow — only the native layer differs (Cordova plugins instead of `@capacitor/*`).
 *
 *   import { ApplaudIQ } from '@applaudiq/embed-cordova';
 *
 *   const embed = ApplaudIQ.init({ key: 'pk_live_xxx', ssoCallback: 'myapp://sso-callback' })
 *     .open({
 *       mode: 'auto',            // 'auto' (server-minted token) | 'manual' (portal login)
 *       token: embedToken,       // auto mode — from your backend /embed/sessions
 *       render: 'fullscreen',    // 'modal' | 'inline' | 'fullscreen'
 *       onReady() {}, onAuthPending() {}, onError(m) {}, onClose() {},
 *     });
 *   // later: embed.close();
 *
 * SSO opens in the SYSTEM BROWSER via `cordova-plugin-inappbrowser` (`open(url, '_system')`) —
 * Google/Microsoft reject WebView OAuth. The one-time code returns on YOUR app's `ssoCallback`
 * deep link — register the scheme in `config.xml` (iOS `CFBundleURLSchemes` + Android
 * intent-filter via `cordova-plugin-customurlscheme`) — and the plugin's `window.handleOpenURL`
 * relays it into the embed. On failure (`?error=`) the SDK fires `onError`.
 *
 * Required Cordova plugins: `cordova-plugin-inappbrowser`, `cordova-plugin-customurlscheme`.
 * (`backbutton` + `deviceready` are Cordova core — no extra plugin.)
 */

// ── ambient Cordova globals (provided at runtime by cordova.js + plugins) ────────────────────
interface CordovaInAppBrowser {
  open(url: string, target?: string, options?: string): unknown;
}
interface CordovaGlobal {
  platformId?: string; // 'ios' | 'android' | 'browser' | …
  InAppBrowser?: CordovaInAppBrowser;
}
declare global {
  interface Window {
    cordova?: CordovaGlobal;
    /** Set by `cordova-plugin-customurlscheme`; called when the app opens via its custom scheme. */
    handleOpenURL?: (url: string) => void;
  }
}

export type RenderMode = 'modal' | 'inline' | 'fullscreen';

export interface EmbedConfig {
  /** Publishable key (`pk_live_…` / `pk_test_…`) from HR → Settings → Embed SDK Keys. */
  key: string;
  /** Portal origin. Defaults to https://recognize.applaudiq.com. */
  baseUrl?: string;
  /**
   * YOUR app's SSO callback deep link, e.g. `myapp://sso-callback`. Register the scheme in
   * `config.xml` (iOS `CFBundleURLTypes` → `CFBundleURLSchemes`; Android intent-filter via
   * `cordova-plugin-customurlscheme`). The SDK sends it to the backend as `native_redirect` so the
   * SSO callback returns to exactly your app — no "Open with" chooser when two Applaud IQ apps are
   * installed. Required for SSO. Defaults to `applaudiq://sso-callback`.
   */
  ssoCallback?: string;
  /**
   * Back-navigation gesture (default true). On **Android** the hardware Back button (the Cordova
   * `backbutton` event) steps back inside the embed instead of bubbling to your app's default
   * (exit/minimize). On **iOS** (no hardware Back) it enables a **left-edge swipe-back** gesture.
   * Both relay an `applaudiq:back` bridge message to the portal, which steps back through its own
   * history or dismisses (`onClose`) at the embed root — the SDK can't traverse the cross-origin
   * iframe history directly. Set false to keep the platform default and disable the iOS swipe.
   */
  backNavigation?: boolean;
}

export interface OpenOptions {
  /** 'auto' uses the server-minted `token`; 'manual' shows the portal's own login. Default 'auto'. */
  mode?: 'auto' | 'manual';
  /** One-time `embedToken` from your backend's `/embed/sessions` call (auto mode). */
  token?: string;
  /** How to render. Default 'fullscreen'. */
  render?: RenderMode;
  /** Container for 'inline' render (element or selector). Required for inline. */
  container?: HTMLElement | string;
  onReady?: () => void;
  onClose?: () => void;
  /** Bad/expired key or token, blocked load, OR a failed SSO sign-in. */
  onError?: (message: string) => void;
  onAuthPending?: () => void;
  /** The user signed out of an auto / host-managed embed — tear down your app's session. */
  onSignOut?: () => void;
}

export interface EmbedHandle {
  /** Tear down the embed (remove the iframe + Cordova listeners). */
  close: () => void;
}

const DEFAULT_BASE = 'https://recognize.applaudiq.com';
const DEFAULT_SSO_CALLBACK = 'applaudiq://sso-callback';
const SSO_PROVIDERS = ['google', 'microsoft'];

const FROM_SDK = 'applaudiq-sdk';
const FROM_EMBED = 'applaudiq-embed';
const MSG = {
  ready: 'applaudiq:ready',
  authenticated: 'applaudiq:authenticated',
  initToken: 'applaudiq:init-token',
  resize: 'applaudiq:resize',
  close: 'applaudiq:close',
  error: 'applaudiq:error',
  authPending: 'applaudiq:auth-pending',
  signout: 'applaudiq:signout',
  ssoRequest: 'applaudiq:sso-request',
  ssoResult: 'applaudiq:sso-result',
  openExternal: 'applaudiq:open-external',
  back: 'applaudiq:back',
} as const;

// ---- native helpers (Cordova-specific; everything else below is platform-agnostic) ----------

/** True on a real Cordova native platform (iOS/Android), false in a plain browser. */
function isNativeCordova(): boolean {
  return typeof window !== 'undefined' && !!window.cordova && window.cordova.platformId !== 'browser';
}

/** Open a URL in the SYSTEM browser (not the WebView) — OAuth IdPs reject embedded WebViews. */
function openSystemBrowser(url: string): void {
  const iab = typeof window !== 'undefined' ? window.cordova?.InAppBrowser : undefined;
  if (iab && typeof iab.open === 'function') {
    iab.open(url, '_system');
    return;
  }
  // Fallback: with cordova-plugin-inappbrowser installed, window.open('_system') also escapes the
  // WebView; without it, a plain window.open is the best we can do.
  try {
    window.open(url, '_system');
  } catch {
    /* no-op */
  }
}

// ---- pure URL/parse helpers (mirror the Capacitor / iOS / Android / RN SDKs) ------------------

/** `scheme://host[:port]` for a URL, lowercased, or null if it can't be parsed. */
function originOf(url: string | null | undefined): string | null {
  if (!url) return null;
  const m = url.match(/^([a-z][a-z0-9.+-]*):\/\/([^/?#]+)/i);
  if (!m) return null;
  return `${m[1].toLowerCase()}://${m[2].toLowerCase()}`;
}

/** Same scheme+host(+port). Both must parse. */
function sameOrigin(a: string | null | undefined, b: string | null | undefined): boolean {
  const oa = originOf(a);
  const ob = originOf(b);
  return oa != null && oa === ob;
}

/**
 * The portal must be served over TLS. `http://` is allowed only for localhost-class hosts (dev).
 * Rejecting a plain-http `baseUrl` stops an attacker origin from hosting the embed.
 */
function isSecureBaseUrl(url: string): boolean {
  const m = url.match(/^([a-z][a-z0-9.+-]*):\/\/([^/?#:]+)/i);
  if (!m) return false;
  const scheme = m[1].toLowerCase();
  const host = m[2].toLowerCase();
  if (scheme === 'https') return true;
  const localhost = host === 'localhost' || host === '127.0.0.1' || host === '10.0.2.2';
  return scheme === 'http' && localhost;
}

/**
 * `<baseUrl>/embed?mode={auto|manual}&k={key}` (+ `&native=1` on a native platform, `&token=` in auto,
 * `&sso_pending=1` on an SSO return, `&env=test` for pk_test_).
 * `native=1` tells the portal it's hosted in a native WebView so it skips reCAPTCHA on the manual-login page
 * (reCAPTCHA can't run in a WebView) and uses the server-minted captcha nonce instead. We send it only when
 * actually running natively — in a plain browser the portal should show its normal reCAPTCHA. The native
 * iOS/Android/RN SDKs signal this by injecting `window.__APPLAUDIQ_EMBED__`; the Cordova SDK loads the portal
 * in a cross-origin iframe (can't inject), so it passes the flag in the URL.
 */
function buildEmbedUrl(
  base: string,
  mode: string,
  key: string,
  native: boolean,
  token?: string,
  ssoPending?: boolean,
): string {
  const m = mode === 'manual' ? 'manual' : 'auto';
  let url = `${base}/embed?mode=${m}`;
  if (native) url += `&native=1`;
  if (key) url += `&k=${encodeURIComponent(key)}`;
  if (m === 'auto' && token) url += `&token=${encodeURIComponent(token)}`;
  // SSO return: re-open the embed in resume mode so the portal exchanges the one-time SSO code we relay
  // (the iframe is on /login by now and can't be script-injected cross-origin). See handleOpenURL + ready below.
  if (ssoPending) url += `&sso_pending=1`;
  if (key && key.startsWith('pk_test_')) url += `&env=test`;
  return url;
}

/** `<baseUrl>/api/v1/auth/sso/{provider}/employee/authorize?native=1[&client_id=][&login_hint=][&native_redirect=]`. */
function buildSsoUrl(
  base: string,
  provider: string,
  clientId?: string | null,
  email?: string | null,
  nativeRedirect?: string | null,
): string {
  const p = SSO_PROVIDERS.includes(provider.toLowerCase()) ? provider.toLowerCase() : 'google';
  let url = `${base}/api/v1/auth/sso/${p}/employee/authorize?native=1`;
  if (clientId && clientId !== 'null') url += `&client_id=${encodeURIComponent(clientId)}`;
  if (email) url += `&login_hint=${encodeURIComponent(email)}`;
  if (nativeRedirect) url += `&native_redirect=${encodeURIComponent(nativeRedirect)}`;
  return url;
}

/**
 * WEB (non-native) SSO authorize URL: `…/authorize?embed=1&k={key}[&client_id=][&login_hint=]&return_uri={here}`.
 * Used when the Cordova app runs in a plain browser — a top-level same-page redirect (no system browser / deep
 * link). The gateway validates `return_uri` against the key's allowed origins and returns `#aiq_sso=<code>` here.
 */
function buildWebSsoUrl(
  base: string,
  provider: string,
  key: string,
  clientId?: string | null,
  email?: string | null,
  returnUri?: string | null,
): string {
  const p = SSO_PROVIDERS.includes(provider.toLowerCase()) ? provider.toLowerCase() : 'google';
  let url = `${base}/api/v1/auth/sso/${p}/employee/authorize?embed=1`;
  if (key) url += `&k=${encodeURIComponent(key)}`;
  if (clientId && clientId !== 'null') url += `&client_id=${encodeURIComponent(clientId)}`;
  if (email) url += `&login_hint=${encodeURIComponent(email)}`;
  if (returnUri) url += `&return_uri=${encodeURIComponent(returnUri)}`;
  return url;
}

/** True when `url` is THIS app's SSO callback (scheme + host match `callback`), regardless of query. */
function isSsoCallback(url: string | null, callback: string | undefined): boolean {
  if (!url || !callback) return false;
  return url.split('?')[0] === callback.split('?')[0];
}

/** Pull a single decoded query param from the callback deep link; null otherwise. */
function callbackParam(url: string, key: 'code' | 'error'): string | null {
  // Stop at `&` AND `#`: the browser/OS appends an empty `#` fragment to the custom-scheme callback,
  // and a query value never contains a raw `#` (it'd be %23), so the fragment must not be captured.
  const m = url.match(new RegExp(`[?&]${key}=([^&#]+)`));
  if (!m || !m[1]) return null;
  // Query values encode spaces as `+` (form-urlencoding); decodeURIComponent only handles `%20`, so
  // normalize `+`→space first or the gateway's error message renders with literal `+` between words.
  const raw = m[1].replace(/\+/g, ' ');
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

class ApplaudIQClient {
  private readonly base: string;
  private readonly origin: string;
  private readonly ssoCallback: string;
  private readonly backNavigation: boolean;
  // True only on a real native platform (iOS/Android). On plain web the SDK falls back to the web-SDK
  // behavior: no `native=1` (so the portal shows its normal reCAPTCHA) and a same-page redirect for SSO.
  private readonly isNative: boolean;

  constructor(private readonly config: EmbedConfig) {
    this.base = (config.baseUrl || DEFAULT_BASE).replace(/\/$/, '');
    this.origin = originOf(this.base) || this.base;
    this.ssoCallback = config.ssoCallback || DEFAULT_SSO_CALLBACK;
    this.backNavigation = config.backNavigation !== false;
    this.isNative = isNativeCordova();
  }

  /**
   * WEB same-page SSO return: read + STRIP the one-time code the gateway appended as `#aiq_sso=<code>`, and
   * persist it in sessionStorage so it survives a framework re-mount that re-runs open(). Cleared on
   * `authenticated`. Returns the code or null. (Native uses the deep-link path instead.)
   */
  private getSsoCode(): string | null {
    if (typeof window === 'undefined') return null;
    try {
      const hash = window.location.hash || '';
      const m = /[#&]aiq_sso=([^&]+)/.exec(hash);
      if (m) {
        const code = decodeURIComponent(m[1]) || null;
        const cleaned = hash.replace(/([#&])aiq_sso=[^&]*/, '$1').replace(/[#&]+$/, '');
        window.history.replaceState(null, '', window.location.pathname + window.location.search + cleaned);
        if (code) {
          try {
            sessionStorage.setItem('aiq_sso_code', code);
          } catch {
            /* sessionStorage unavailable */
          }
        }
        return code;
      }
      try {
        return sessionStorage.getItem('aiq_sso_code');
      } catch {
        return null;
      }
    } catch {
      return null;
    }
  }

  open(options: OpenOptions = {}): EmbedHandle {
    const noop: EmbedHandle = { close: () => {} };
    const mode = options.mode === 'manual' ? 'manual' : 'auto';
    const render: RenderMode = options.render || 'fullscreen';

    // Refuse an insecure portal origin: the one-time token + session cookies must never travel over
    // cleartext. HTTPS required; http tolerated only for a localhost-class dev portal.
    if (!isSecureBaseUrl(this.base)) {
      options.onError?.('insecure_base_url');
      return noop;
    }

    // ── mount the iframe ─────────────────────────────────────────────────────────────────────
    // WEB same-page SSO return: the gateway handed back `#aiq_sso=<code>` on this page — open the embed in
    // resume mode and relay it once the iframe is ready (the native path uses the deep link instead).
    const webSsoCode = this.isNative ? null : this.getSsoCode();
    const iframe = document.createElement('iframe');
    iframe.src = buildEmbedUrl(
      this.base,
      mode,
      this.config.key,
      this.isNative,
      options.token,
      !!webSsoCode,
    );
    iframe.setAttribute('allow', 'clipboard-write; clipboard-read');
    iframe.style.border = '0';
    iframe.style.width = '100%';
    iframe.style.height = '100%';

    let overlay: HTMLElement | null = null;
    const containerEl =
      typeof options.container === 'string'
        ? document.querySelector<HTMLElement>(options.container)
        : options.container || null;

    if (render === 'inline') {
      if (!containerEl) {
        options.onError?.('missing_container');
        return noop;
      }
      containerEl.appendChild(iframe);
    } else {
      // modal + fullscreen both use a fixed full-viewport overlay (native apps have no "page" chrome).
      overlay = document.createElement('div');
      overlay.style.position = 'fixed';
      overlay.style.inset = '0';
      overlay.style.zIndex = '2147483647';
      overlay.style.background = render === 'modal' ? 'rgba(0,0,0,0.5)' : '#ffffff';
      const frameWrap =
        render === 'modal'
          ? Object.assign(document.createElement('div'), {} as HTMLDivElement)
          : overlay;
      if (render === 'modal') {
        frameWrap.style.position = 'absolute';
        frameWrap.style.inset = '24px';
        frameWrap.style.borderRadius = '12px';
        frameWrap.style.overflow = 'hidden';
        frameWrap.style.background = '#ffffff';
        overlay.appendChild(frameWrap);
      }
      frameWrap.appendChild(iframe);

      // ── iOS left-edge swipe-back ─────────────────────────────────────────────────────────────
      // iOS has no hardware Back button, and the portal is a cross-origin iframe so the WebView's own
      // swipe-back can't traverse its history (and touch events over the iframe never reach us).
      // Overlay a thin left-edge catcher in the host layer and relay a rightward edge-swipe as the
      // SAME `MSG.back` the Android hardware button sends — the portal steps back / replies `close`
      // at root. Gated on iOS native + backNavigation. NB: the ~20px edge zone swallows taps there
      // (matches the iOS system back-gesture zone). Removed automatically with `overlay` in teardown.
      if (this.backNavigation && window.cordova?.platformId === 'ios') {
        const edge = document.createElement('div');
        edge.style.cssText =
          'position:absolute;left:0;top:0;bottom:0;width:20px;z-index:1;touch-action:pan-y;';
        // Pointer Events (with capture) so a swipe that starts in the 20px zone keeps tracking as it
        // travels right, past the strip — `pointerType` is 'touch' on a real finger.
        let startX = Number.NaN;
        let startY = 0;
        let fired = false;
        edge.addEventListener('pointerdown', (e: PointerEvent) => {
          startX = e.clientX;
          startY = e.clientY;
          fired = false;
          try {
            edge.setPointerCapture(e.pointerId);
          } catch {
            /* capture unsupported — pointermove on the strip still covers the start of the gesture */
          }
        });
        const maybeBack = (e: PointerEvent) => {
          if (fired || Number.isNaN(startX)) return;
          const dx = e.clientX - startX;
          const dy = e.clientY - startY;
          if (dx > 60 && Math.abs(dy) < 40) {
            fired = true;
            send(MSG.back);
          }
        };
        edge.addEventListener('pointermove', maybeBack);
        edge.addEventListener('pointerup', maybeBack);
        frameWrap.appendChild(edge);
      }

      document.body.appendChild(overlay);
    }

    // ── teardown ─────────────────────────────────────────────────────────────────────────────
    let closed = false;
    const cleanups: Array<() => void> = [];
    const teardown = () => {
      if (closed) return;
      closed = true;
      window.removeEventListener('message', onMessage);
      for (const c of cleanups) {
        try {
          c();
        } catch {
          /* best-effort cleanup */
        }
      }
      (overlay || iframe).remove();
    };
    const handle: EmbedHandle = { close: teardown };

    // ── bridge: send into the iframe ─────────────────────────────────────────────────────────
    const send = (type: string, payload?: unknown) => {
      iframe.contentWindow?.postMessage({ source: FROM_SDK, type, payload }, this.origin);
    };

    // ── SSO ──────────────────────────────────────────────────────────────────────────────────
    let ssoInFlight = false;
    // The one-time SSO code, held until the (re-loaded, sso_pending) iframe posts `ready` — then relayed once
    // for the portal to exchange. Seeded from the WEB same-page return (#aiq_sso) or the native deep link.
    let pendingSsoCode: string | null = webSsoCode;
    const openSSO = (provider: string, clientId?: string | null, email?: string | null) => {
      if (this.isNative) {
        // Native: open the IdP in the SYSTEM BROWSER; the one-time code returns on the app's deep link.
        const url = buildSsoUrl(this.base, provider, clientId, email, this.ssoCallback);
        ssoInFlight = true;
        openSystemBrowser(url);
        return;
      }
      // Web: top-level same-page redirect (no new tab); the gateway returns `#aiq_sso=<code>` here and open()
      // resumes on the next load (see webSsoCode above). Mirrors the @applaudiq/embed-web SDK.
      const url = buildWebSsoUrl(this.base, provider, this.config.key, clientId, email, window.location.href);
      window.location.assign(url);
    };

    // ── native deep-link return: <ssoCallback>?code=… (success) or ?error=… (failure) ──────────
    // `cordova-plugin-customurlscheme` invokes `window.handleOpenURL(url)` when the app is re-opened via its
    // custom scheme. We install our handler (chaining any prior one for non-SSO links) and restore it on teardown.
    if (this.isNative) {
      const prevHandleOpenURL = window.handleOpenURL;
      const handleOpenURL = (url: string) => {
        if (!url || !ssoInFlight || !isSsoCallback(url, this.ssoCallback)) {
          // not ours — let any previously-registered handler deal with it
          if (typeof prevHandleOpenURL === 'function') prevHandleOpenURL(url);
          return;
        }
        ssoInFlight = false;
        const code = callbackParam(url, 'code');
        if (code) {
          // By now the iframe is on /login (the embed switched there in manual mode) and it's cross-origin,
          // so we can't script-inject the exchange. Re-load the iframe in resume mode (`sso_pending=1`) and
          // relay the one-time code once it posts `ready` (see onMessage) — the portal then exchanges it.
          pendingSsoCode = code;
          iframe.src = buildEmbedUrl(this.base, mode, this.config.key, this.isNative, undefined, true);
          return;
        }
        // SSO failed (e.g. the IdP email isn't an employee of this tenant). Notify the host AND show the
        // failure INSIDE the embed. NB: /sso-callback is X-Frame-Options: DENY, so it's BLANK in our cross-origin
        // iframe — re-load the FRAMEABLE embed page with `&sso_error=` instead; it renders the same
        // "Authentication Failed" card (its "Return to login" returns to the embed login to retry).
        const err = callbackParam(url, 'error') || 'sso_failed';
        options.onError?.(err);
        pendingSsoCode = null;
        iframe.src =
          buildEmbedUrl(this.base, mode, this.config.key, this.isNative) +
          '&sso_error=' +
          encodeURIComponent(err);
      };
      window.handleOpenURL = handleOpenURL;
      cleanups.push(() => {
        // Only restore if no later open() replaced us in the meantime.
        if (window.handleOpenURL === handleOpenURL) window.handleOpenURL = prevHandleOpenURL;
      });
    }

    // ── Android hardware Back (Cordova `backbutton`) → step back inside the embed ───────────────
    // The portal is a cross-origin iframe, so we can't traverse its history from here (unlike the native
    // Android SDK's webView.goBack()). Instead ask the embed to go back via the bridge; the portal navigates
    // back in its own history and only replies with `close` when it's already at the embed root — which the
    // onMessage `close` handler below tears down. (backNavigation:false keeps the platform default.)
    if (this.backNavigation && this.isNative) {
      const onBackButton = () => send(MSG.back);
      document.addEventListener('backbutton', onBackButton);
      cleanups.push(() => document.removeEventListener('backbutton', onBackButton));
    }

    // ── bridge: receive from the embed ───────────────────────────────────────────────────────
    const onMessage = (e: MessageEvent) => {
      // Only the portal origin may drive the bridge.
      if (e.origin && e.origin !== 'null' && !sameOrigin(e.origin, this.base)) return;
      const d = e.data as
        | { source?: string; type?: string; payload?: Record<string, unknown> }
        | null;
      if (!d || d.source !== FROM_EMBED) return;
      switch (d.type) {
        case MSG.ready:
        case MSG.authenticated:
          // SSO return: the iframe re-loaded in sso_pending mode is ready — relay the code once so the portal
          // exchanges it (→ authenticated → dashboard). Works for both the native deep link and the web
          // same-page (#aiq_sso) return.
          if (pendingSsoCode) {
            send(MSG.ssoResult, { code: pendingSsoCode });
            pendingSsoCode = null;
          }
          if (d.type === MSG.authenticated) {
            // Signed in — drop the persisted web SSO code so a later reload doesn't replay a spent code.
            try {
              sessionStorage.removeItem('aiq_sso_code');
            } catch {
              /* sessionStorage unavailable */
            }
          }
          if (mode === 'auto' && options.token) send(MSG.initToken, { token: options.token });
          options.onReady?.();
          break;
        case MSG.authPending:
          options.onAuthPending?.();
          break;
        case MSG.error:
          options.onError?.((d.payload?.message as string) || 'error');
          break;
        case MSG.close:
          options.onClose?.();
          teardown();
          break;
        case MSG.signout:
          options.onSignOut?.();
          break;
        case MSG.resize:
          if (render === 'inline' && typeof d.payload?.height === 'number') {
            iframe.style.height = `${d.payload.height}px`;
          }
          break;
        case MSG.ssoRequest: {
          const raw = String(d.payload?.provider || 'google').toLowerCase();
          const provider = SSO_PROVIDERS.includes(raw) ? raw : 'google';
          const rawClient = d.payload?.clientId;
          const clientId =
            rawClient == null ? null : typeof rawClient === 'string' ? rawClient : String(rawClient);
          openSSO(provider, clientId, (d.payload?.email as string) || null);
          break;
        }
        case MSG.openExternal: {
          // Reward-store downloads / payment / OAuth: open the URL in the system browser.
          const url = typeof d.payload?.url === 'string' ? d.payload.url : '';
          if (/^https?:\/\//i.test(url)) openSystemBrowser(url);
          break;
        }
      }
    };
    window.addEventListener('message', onMessage);

    return handle;
  }
}

/** Create an embed client for a publishable key. */
export function init(config: EmbedConfig): ApplaudIQClient {
  return new ApplaudIQClient(config);
}

/** Namespaced entry point — `ApplaudIQ.init(...)`. */
export const ApplaudIQ = { init };

export type { ApplaudIQClient };
