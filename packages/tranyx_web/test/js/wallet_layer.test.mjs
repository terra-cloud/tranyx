// Runs the wallet layer of web/index.html (getSolanaProvider .. connectSolanaWallet) against fake
// providers: node --test test/js/wallet_layer.test.mjs   (no browser, no wallet needed)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const html = readFileSync(fileURLToPath(new URL('../../web/index.html', import.meta.url)), 'utf8');
const src = html.slice(html.indexOf('    function getSolanaProvider(type) {'), html.indexOf('    window.getSolanaPublicKeyIfConnected'));

function boot({ ua = 'Mozilla/5.0 (Macintosh)', href = 'https://dev.tranyx.app/?x=1', store = {}, injected = {} } = {}) {
  const nav = { href: '' };
  const window = {
    ...injected,
    location: { get href() { return nav.href || href; }, set href(v) { nav.href = v; }, origin: new URL(href).origin },
    history: { replaceState: (_a, _b, u) => { window._replaced = u; } },
    dispatchEvent() {},
    CustomEvent: class { constructor(n, o) { this.n = n; this.detail = o?.detail; } },
  };
  const localStorage = { getItem: (k) => store[k] ?? null, setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; } };
  const ctx = vm.createContext({ window, localStorage, navigator: { userAgent: ua }, URL, setTimeout, Date, Error, console, encodeURIComponent });
  vm.runInContext(src, ctx);
  return { window, nav, store };
}
const fakeProvider = (key = 'KEY1', extra = {}) => {
  const p = { publicKey: null, connects: 0, on() {}, off() {}, async connect() { p.connects++; p.publicKey = { toString: () => key }; return { publicKey: p.publicKey }; }, ...extra };
  return p;
};

test('connect uses the SELECTED wallet, never silently another one', async () => {
  const phantom = fakeProvider('PH'); const solflare = fakeProvider('SF');
  const { window, store } = boot({ injected: { phantom: { solana: phantom }, solflare }, store: { selectedSolanaWallet: 'solflare' } });
  assert.equal(await window.connectSolanaWallet('solflare'), 'SF');
  assert.equal(solflare.connects, 1); assert.equal(phantom.connects, 0);
  assert.equal(store.selectedSolanaWallet, 'solflare');
});

test('a selected wallet that is not installed is an error, not a swap to another wallet (desktop)', async () => {
  const phantom = fakeProvider('PH');
  const { window } = boot({ injected: { phantom: { solana: phantom } }, store: { selectedSolanaWallet: 'backpack' } });
  await assert.rejects(window.connectSolanaWallet('backpack'), /Backpack Wallet is not installed/);
  assert.equal(phantom.connects, 0);
});

test('nothing ever selected: falls back to the installed wallet', async () => {
  const sf = fakeProvider('SF');
  const { window } = boot({ injected: { solflare: sf } });
  assert.equal(await window.connectSolanaWallet('phantom'), 'SF');
});

test('trust wallet is found under window.trustwallet and window.trustWallet', async () => {
  for (const k of ['trustwallet', 'trustWallet']) {
    const t = fakeProvider('TR');
    const { window } = boot({ injected: { [k]: { solana: t } }, store: { selectedSolanaWallet: 'trust' } });
    assert.equal(await window.connectSolanaWallet('trust'), 'TR');
  }
});

test('mobile browser without a provider deep-links into the chosen wallet app and stops', async () => {
  const ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)';
  for (const [wallet, host] of [['phantom', 'https://phantom.app/ul/browse/'], ['solflare', 'https://solflare.com/ul/v1/browse/'], ['backpack', 'https://backpack.app/ul/v1/browse/'], ['trust', 'https://link.trustwallet.com/open_url?coin_id=501&url=']]) {
    const { window, nav } = boot({ ua, store: { selectedSolanaWallet: wallet } });
    await assert.rejects(window.connectSolanaWallet(wallet), /WALLET_APP_REDIRECT/);
    assert.ok(nav.href.startsWith(host), nav.href);
    const target = decodeURIComponent(nav.href.slice(host.length).split('?ref=')[0].split('&')[0]);
    const u = new URL(target);
    assert.equal(u.origin, 'https://dev.tranyx.app');
    assert.equal(u.searchParams.get('wallet'), wallet);
    assert.equal(u.searchParams.get('walletAction'), 'signin');
    assert.equal(u.searchParams.get('x'), '1'); // keeps the current page
  }
});

test('mobile browser WITH an injected provider (in the wallet app) connects directly', async () => {
  const p = fakeProvider('PH');
  const { window, nav } = boot({ ua: 'Android', injected: { phantom: { solana: p } }, store: { selectedSolanaWallet: 'phantom' } });
  assert.equal(await window.connectSolanaWallet('phantom'), 'PH');
  assert.equal(nav.href, '');
});

test('launch intent is read once and stripped from the URL', () => {
  const { window } = boot({ href: 'https://dev.tranyx.app/?wallet=phantom&walletAction=signin&x=1' });
  assert.deepEqual(JSON.parse(window.consumeWalletLaunchIntent()), { wallet: 'phantom', action: 'signin' });
  assert.equal(window._replaced, '/?x=1');
  const none = boot({ href: 'https://dev.tranyx.app/?wallet=evil&walletAction=signin' });
  assert.equal(none.window.consumeWalletLaunchIntent(), null);
  assert.equal(boot().window.consumeWalletLaunchIntent(), null);
});

test('a wallet that rejects the connect request surfaces its error', async () => {
  const p = fakeProvider('PH', { async connect() { const e = new Error('User rejected the request.'); e.code = 4001; throw e; } });
  const { window } = boot({ injected: { phantom: { solana: p } }, store: { selectedSolanaWallet: 'phantom' } });
  await assert.rejects(window.connectSolanaWallet('phantom'), /User rejected/);
});
