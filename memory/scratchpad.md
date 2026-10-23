# Scratchpad — web redesign Batch A

## W05 live data
- Guest browse uses Firestore open jobs (`getAvailableJobs(nyxian)`) + realtime `rentals` / `properties` listeners (public read).
- No Figma sample cards. Empty copy when query empty.
- Exact address redacted for guests (approx distance only).
- Verify: Sign In → Browse as guest → Top Services / Open Gigs / Nearby Rentals show tranyx-dev rows or empty states.
- Jobs tab as guest also uses `availableJobs`. Transit uses realtime streams.

## W01 verify (DevTools device mode)
- ≥1024: left brand 680 + right form card 440, blobs drift
- 640–1023: top white band ~300px (logo + one-line headline + short blurb), card 480 centered
- <640: logo + headline + full-width card, px-16 (Tailwind px-4)
- Theme: clear `tranyx_theme_preference` → OS Appearance flips UI
- prefers-reduced-motion: blobs stop

## Next after W01 solid
W10 Nyxian Dashboard (8:82), then W20+
