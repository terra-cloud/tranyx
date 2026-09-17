---
name: maestro-e2e
description: End-to-End (E2E) mobile and cross-platform UI testing using Maestro. Use whenever the user requests E2E testing, UI automation, user flow verification, or Maestro test execution for mobile apps.
---

# Maestro E2E Testing Skill

## Overview
Maestro is the industry-standard UI automation and E2E testing framework for Flutter, Android, iOS, and React Native. Maestro tests are declarative YAML flows that execute actions (`tapOn`, `inputText`, `scroll`, `assertVisible`, `copyTextFrom`, etc.) directly on running simulators, emulators, or physical devices.

Maestro CLI binary path: `/Users/zeuscajurao/.maestro/bin/maestro` (or `~/.maestro/bin/maestro`).

---

## 1. Flow File Structure

Maestro test flows are written in YAML and stored in `.maestro/` or `e2e/maestro/` (e.g. `.maestro/booking_flow.yaml`).

### Basic Syntax
```yaml
appId: com.tranyx.tranyx_mobile
---
- launchApp:
    clearState: true # or false to preserve session

- assertVisible: "Search"
- tapOn: "Rent"
- tapOn: "🚗 Vehicles"

# Input text into search fields
- tapOn: "Search destination or car model"
- inputText: "Toyota"

# Assert element presence
- assertVisible: "Toyota Fortuner"
- tapOn: "Toyota Fortuner"

# Scroll if needed
- scroll
- assertVisible: "Book Vehicle"
- tapOn: "Book Vehicle"

# Verification
- assertVisible: "AWAITING HOST APPROVAL"
```

---

## 2. Common Maestro Commands & Selectors

### Selectors
- **By Text:** `- tapOn: "Approve"`
- **By Regex:** `- tapOn: ".*Fortuner.*"`
- **By ID / Key:** `- tapOn: { id: "booking_cancel_btn" }`
- **Relative Positioning:**
  ```yaml
  - tapOn:
      text: "Cancel"
      below: "Toyota Fortuner"
  ```
- **Conditional Actions:**
  ```yaml
  - runFlow:
      when:
        visible: "Allow Notifications"
      commands:
        - tapOn: "Allow"
  ```

### Assertions
- `- assertVisible: "PENDING"`
- `- assertNotVisible: "Error"`
- `- assertTrue: "${output.status == 'Approved'}"`

### Gestures & Input
- `- scroll` / `- scrollUntilVisible: { element: { text: "Complete Lease" } }`
- `- swipe: { direction: LEFT }`
- `- back`
- `- hideKeyboard`

---

## 3. Running Maestro Tests

Run tests using `run_command` with `BypassSandbox: true` (since Maestro interacts with iOS Simulator / Android Emulator via ADB / xcrun):

```bash
# Run a specific flow
/Users/zeuscajurao/.maestro/bin/maestro test .maestro/booking_flow.yaml

# Run all flows in a directory
/Users/zeuscajurao/.maestro/bin/maestro test .maestro/

# Run with format output
/Users/zeuscajurao/.maestro/bin/maestro test --format junit .maestro/
```

---

## 4. Kelvin's E2E Protocol

Whenever E2E testing is requested:
1. **Target App Discovery**: Confirm target package ID (e.g. `com.tranyx.tranyx_mobile` or iOS bundle identifier).
2. **Flow Authoring**: Draft clean, resilient YAML flows in `.maestro/<feature>_flow.yaml` without hardcoded arbitrary delays (prefer `assertVisible` or `waitForAnimationToEnd`).
3. **Execution**: Run `/Users/zeuscajurao/.maestro/bin/maestro test <flow>.yaml` on active simulator/device.
4. **Triage & Reporting**: Capture failure screenshots or logs, outputting clear `PASS` or `FAIL` status with repro steps.
