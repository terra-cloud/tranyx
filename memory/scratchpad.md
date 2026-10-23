# Scratchpad — web redesign Batch A

## Auth stack (priority — current)
- W01 Sign In — split + animated blobs (prior)
- W02 Join / W03 Create / W04 Verification / Forgot — AuthBrandShell
- Shared motion: `lib/client/widgets/auth_brand_shell.dart` + `.brand-blob*` CSS (w01-blob keyframes, reduced-motion)
- Paths @ http://localhost:8080/
  - Sign In → Get Started → Join (W02) → Continue → Create (W03) → Create Account → Verification (W04) → Back to Login
  - Sign In → Forgot password? → Reset → Send reset link (live Firebase)
- System theme; live Firebase register sends verification email

## Filters WIP paused
- `78238b9` GigFilterEngine category chips — resume after auth looks good
