# Skill: Implement a Flutter Screen (Tranyx Mobile Architecture)

## Purpose
Guides an agent through implementing a full-fidelity Flutter screen for the Tranyx mobile app, using Riverpod for state management and GoRouter for navigation.

## Project Architecture
```
lib/
├── main.dart                 # Entry point, flavor-based Firebase init
├── app.dart                  # MaterialApp.router with GoRouter
├── features/
│   ├── auth/                 # Login, Register, KYC screens
│   ├── home/                 # Home tab
│   ├── jobs/                 # Jobs & gigs tab (list, create, details, apply)
│   ├── transit/              # Transit tab (rent/host)
│   └── profile/              # Profile tab (personal, professional, payment, trust, support)
├── shared/
│   ├── widgets/              # Reusable UI components
│   ├── models/               # Data models (UserProfile, Job, JobGroup, etc.)
│   └── services/             # Firebase, Gemini, Web3 services
└── providers/                # Riverpod providers
```

## Screen Template
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class XxxScreen extends ConsumerWidget {
  const XxxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Access providers:
    // final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // zinc-950
      body: SafeArea(
        child: // your content
      ),
    );
  }
}
```

## Design Tokens
| Token | Value |
|---|---|
| Dark background | `Color(0xFF09090B)` (zinc-950) |
| Card background | `Color(0xFF18181B)` (zinc-900) |
| Card border | `Color(0xFF27272A)` (zinc-800) |
| Primary accent | `Color(0xFF4F46E5)` (indigo-600) |
| Active gradient | `LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFFA855F7)])` |
| Text primary | `Color(0xFFFAFAFA)` (zinc-50) |
| Text secondary | `Color(0xFF71717A)` (zinc-500) |
| Font | `'Inter'` (add to pubspec fonts) |
| Border radius | `BorderRadius.circular(16)` (2xl), `BorderRadius.circular(24)` (3xl) |

## Navigation
- Use GoRouter with `go(context, '/path')` — not `Navigator.push`
- Named routes defined in `app.dart` or a dedicated `router.dart`
- Bottom tab navigation uses `StatefulShellRoute` for persistent tab state

## State Management Rules
1. Use `ConsumerWidget` for read-only state
2. Use `ConsumerStatefulWidget` for local state + provider access
3. Provider naming: `xyzProvider` for state, `xyzNotifierProvider` for notifiers
4. Never call `ref.read` inside `build()` — only in callbacks/effects

## Common Patterns
```dart
// Conditional rendering
if (isLoading) const CircularProgressIndicator() else content,

// Gradient button
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFFA855F7)]),
    borderRadius: BorderRadius.circular(16),
  ),
  child: ElevatedButton(...),
)

// Card
Container(
  padding: EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Color(0xFF18181B),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Color(0xFF27272A)),
  ),
  child: ...,
)
```
