# Google Navigation Map – Jaspr Implementation Plan

## Overview
Build a Google Maps-style navigation component in Jaspr using Leaflet.js interop.

---

## Phase 1: Architectural Foundation & Agent State
- Define `NavigationAgent` Dart model (coordinates, waypoints, heading, speed, status)
- Implement state management (stream-based or inherited component)
- Decouple server/client: heavy background logic on server/isolate, clean UI component on client

**Milestone:** `NavigationAgent` module holding path, GPS speed, heading, and executing state transitions independently of UI.

---

## Phase 2: JS Interop & Map Synchronization
- Expand `leaflet_interop.dart` to handle: map init, marker mutations, path recalculations
- Build Jaspr `StatefulComponent` that creates `<div id="map">` and mounts Leaflet
- Sync state → visual: when `agent.currentLocation` changes, call Leaflet interop to pan/animate the vehicle marker

**Milestone:** Jaspr page that initializes Leaflet and updates a vehicle marker dynamically from a Dart stream.

---

## Phase 3: Routing Engine Integration & Instructions
- Integrate Leaflet Routing Machine (LRM) with OSRM (free) or Mapbox/GraphHopper backend
- Expose `routesfound` JS event back to Dart (trip distance, turns remaining, text steps)
- Build turn-by-turn HUD overlay in Jaspr HTML/CSS (e.g. "In 300m, turn left onto Main Street")

**Milestone:** User inputs destination → blue route ribbon renders → side panel shows full text directions.

---

## Phase 4: Live Telemetry, Simulation & Optimization
- Hook into HTML5 Geolocation API (`watchPosition`) for live GPS
- Build mock telemetry engine (simulate marker moving along polyline for testing)
- Optimize Leaflet JS/CSS loading in Jaspr build pipeline (conditional loading, Core Web Vitals safe)

**Milestone:** Full navigation with smooth marker animation, live/simulated tracking, off-route recalculation, lightweight delivery.

---

## Notes
- Style to closely match Google Navigation UI (dark map theme, route ribbon, bottom instruction drawer)
- This lives inside the `tranyx_web` Jaspr app, likely as the Transit view or a dedicated NavigationView
- The `TransitView` is currently UI-only — this can power the real map feature there
