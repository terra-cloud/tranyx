# Scratchpad — web redesign Batch A

## Theme
- Key: `localStorage.tranyx_theme_preference` = light|dark|absent(system)
- Verify: remove key, flip macOS Appearance → UI flips; moon toggle pins preference

## Done
- W01 Sign In → http://localhost:8080/ (logged out)
- W05 Guest Browse → Sign In → "Browse as guest" → guest Home
- Paths: guest Dashboard/Jobs/Rentals browse; Messages/Profile locked → signup

## Next
W10 Nyxian Dashboard, W20 Jobs, W22 details, W30 Rentals, W40 Messages, W50 Profile, W54 Withdraw

## W10 ready
- Figma node 8:82 (Nyxian Dashboard 1440). Redesign home_view for authenticated Nyxian; reuse guest chrome patterns (sidebar labels) when touching auth chrome.
- Jobs empty in guest until public reads exist — static W05 cards intentional.
