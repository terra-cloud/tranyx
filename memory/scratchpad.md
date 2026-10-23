# Scratchpad — web redesign Batch A

## Theme (hard constraint)
- Storage key: `localStorage.tranyx_theme_preference` = `light` | `dark` | absent(system)
- API: `setThemePreference` / `toggleTheme` / `clearThemePreference` / `followsSystemTheme`
- Header moon toggle = explicit persist via `toggleTheme()`
- Clear preference (future settings) → follow OS again
- Verify: DevTools → Application → remove `tranyx_theme_preference`, flip macOS Appearance → UI should flip

## Active
- W01 done @ 881fb75; theme fix next commit; then W05 guest browse
- Localhost: http://localhost:8080/
- Serve: `cd packages/tranyx_web && dart run shared:generate_env && jaspr serve --dart-define=ENV=dev`

## Next
W05 Guest Browse + wire from Sign In; then W10–W54
