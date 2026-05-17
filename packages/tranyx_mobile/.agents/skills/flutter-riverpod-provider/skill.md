# Skill: Implement Riverpod Provider (Tranyx Mobile)

## Purpose
Guides an agent through creating a correct, idiomatic Riverpod provider for the Tranyx mobile app.

## Provider Types
| Use Case | Provider Type |
|---|---|
| Sync derived state | `Provider<T>` |
| Async data (one-shot) | `FutureProvider<T>` |
| Async stream | `StreamProvider<T>` |
| Mutable notifier | `NotifierProvider<N, T>` |
| Async mutable notifier | `AsyncNotifierProvider<N, T>` |
| State with family params | `xxxProvider.family<T, Arg>` |

## Standard Auth Provider Pattern
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../services/firebase_service.dart';

// Service provider
final firebaseServiceProvider = Provider<FirebaseService>((ref) => FirebaseService());

// Current user (async)
final currentUserProvider = FutureProvider<UserProfile?>((ref) async {
  final service = ref.watch(firebaseServiceProvider);
  return service.getCurrentUser();
});

// Auth state notifier
class AuthNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async => null;

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(firebaseServiceProvider);
      return service.signIn(email, password);
    });
  }

  Future<void> signOut() async {
    await ref.read(firebaseServiceProvider).signOut();
    state = const AsyncValue.data(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserProfile?>(AuthNotifier.new);
```

## Jobs Provider Pattern
```dart
final jobsListProvider = FutureProvider.family<List<Job>, String>((ref, accountType) async {
  final service = ref.watch(firebaseServiceProvider);
  return service.getJobs(accountType: accountType);
});

class JobCreateNotifier extends Notifier<JobDraft> {
  @override
  JobDraft build() => JobDraft.empty();

  void updateTitle(String title) => state = state.copyWith(title: title);
  void updateCategory(CategoryItem cat) => state = state.copyWith(category: cat);
  // ...
}

final jobCreateProvider = NotifierProvider<JobCreateNotifier, JobDraft>(JobCreateNotifier.new);
```

## Rules
1. Keep providers in `lib/providers/` — one file per domain (auth, jobs, transit, profile)
2. Use `ref.invalidate(provider)` to refresh, never manually manage async state
3. Use `AsyncValue.guard()` to convert exceptions to `AsyncError`
4. Pass provider refs between services using `ref.read` in callbacks only
5. Use `keepAlive: true` on providers that must persist across tab switches
