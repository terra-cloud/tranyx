import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/features/auth/presentation/auth_ui_helper.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tranyx_mobile/flavors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/core/services/trust_wallet_service.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';
import 'package:reown_appkit/reown_appkit.dart';

/// Checks if a wallet app is installed by probing all candidate schemes defined
/// in [WalletInfo.candidateConnectSchemes], falling back to [WalletInfo.nativeScheme].
///
/// This mirrors the detection logic in payment_pane.dart's `_checkInstalledWallets`,
/// which correctly identifies Trust Wallet by trying multiple schemes since the bare
/// `trust://` scheme doesn't resolve on most OS versions without a path/param.
Future<bool> _isWalletInstalled(WalletInfo wallet) async {
  final schemesToCheck = wallet.candidateConnectSchemes.isNotEmpty
      ? wallet.candidateConnectSchemes
      : [wallet.nativeScheme];

  for (final scheme in schemesToCheck) {
    try {
      if (await canLaunchUrl(Uri.parse(scheme))) return true;
    } catch (_) {}
  }
  return false;
}

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  /// Trust Wallet AppKit modal — kept alive for the duration of the auth flow.
  ReownAppKitModal? _trustModal;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _trustModal?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _launchUrl(String path) async {
    final String domain;
    switch (F.appFlavor) {
      case Flavor.dev:
        domain = 'dev.tranyx.app';
        break;
      case Flavor.uat:
        domain = 'uat.tranyx.app';
        break;
      case Flavor.production:
        domain = 'tranyx.app';
        break;
    }
    final url = Uri.parse('https://$domain$path');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showError('Could not launch $url');
      }
    } catch (e) {
      _showError('Could not launch $url: $e');
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authControllerProvider)
          .signInWithEmailAndPassword(email, password);
      // Success will trigger state change in authControllerProvider which will be handled by the main app wrapper
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'An error occurred during login');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authControllerProvider).signInWithGoogle();
      // On successful Google Sign-In, we might need to set a default account type if it's a new user
      // But for login, it usually just signs them in.
    } catch (e) {
      _showError('Google Sign-In failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);

    return AuthUiHelper.buildAuthScaffold(
      context: context,
      isDarkMode: isDarkMode,
      isLoading: _isLoading,
      actions: [
        IconButton(
          icon: Icon(
            isDarkMode ? Icons.light_mode : Icons.dark_mode,
            color: isDarkMode
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
          ),
          onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthUiHelper.buildHeader(
            title: "Welcome back",
            subtitle: "Enter your details to access your account.",
            isDarkMode: isDarkMode,
            icon: Icons.widgets,
          ),
          const SizedBox(height: 32),
          UIHelpers.buildTextField(
            Icons.mail_outline,
            "Email address",
            isDarkMode,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          UIHelpers.buildTextField(
            Icons.lock_outline,
            "Password",
            isDarkMode,
            isPassword: true,
            controller: _passwordController,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 32),
          UIHelpers.buildPrimaryButton("Log In", _handleLogin, isDarkMode),
          const SizedBox(height: 16),
          AuthUiHelper.buildGoogleButton(
            isDarkMode: isDarkMode,
            onPressed: _handleGoogleSignIn,
          ),
          const SizedBox(height: 16),
          AuthUiHelper.buildWalletButton(
            isDarkMode: isDarkMode,
            onPressed: _handleWalletSignIn,
          ),
          const SizedBox(height: 24),
          RichText(
            text: TextSpan(
              text: "New to Tranyx? ",
              style: TextStyle(
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: "Create an account",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : AppColors.indigo,
                    fontWeight: FontWeight.bold,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => ref.read(authViewProvider.notifier).state =
                        'register-path',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl('/terms-of-use'),
                child: Text(
                  "Terms of Use",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : AppColors.indigo,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "•",
                style: TextStyle(
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _launchUrl('/privacy-policy'),
                child: Text(
                  "Privacy Policy",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : AppColors.indigo,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleWalletSignIn() {
    final isDarkMode = ref.read(themeModeProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final isDarkMode = ref.watch(themeModeProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Select a Wallet",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? AppColors.darkText
                            : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Choose which Solana wallet application you want to continue with.",
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: kSupportedWallets.map((wallet) {
                          return _buildWalletOptionAsync(
                            context: context,
                            wallet: wallet,
                            isDarkMode: isDarkMode,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWalletOptionAsync({
    required BuildContext context,
    required WalletInfo wallet,
    required bool isDarkMode,
  }) {
    return FutureBuilder<bool>(
      future: _isWalletInstalled(wallet),
      builder: (context, snapshot) {
        final isInstalled = snapshot.data ?? false;
        final isChecking = !snapshot.hasData;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.darkBg : AppColors.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                wallet.assetPath,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.account_balance_wallet,
                  color: isDarkMode ? Colors.white : AppColors.lightText,
                ),
              ),
            ),
            title: Text(
              wallet.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            subtitle: isChecking
                ? null
                : Text(
                    isInstalled ? 'Tap to connect' : 'Not installed',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
            trailing: isChecking
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.indigo,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isInstalled
                          ? AppColors.indigo.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isInstalled ? 'Connect' : 'Install',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isInstalled ? AppColors.indigo : Colors.orange,
                      ),
                    ),
                  ),
            onTap: () async {
              Navigator.of(context).pop();
              if (isInstalled) {
                await _connectWallet(wallet.id);
              } else {
                await _openStore(wallet.id);
              }
            },
          ),
        );
      },
    );
  }

  /// Connects Phantom or Solflare via the NaCl deep-link protocol.
  /// For Trust Wallet, delegates to the WalletConnect v2 (AppKit) flow.
  Future<void> _connectWallet(String walletId) async {
    if (walletId == 'trust') {
      await _connectTrustWallet();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final phantomService = ref.read(phantomServiceProvider);
      final connectUri = await phantomService.generateConnectUri(
        walletType: walletId,
      );

      debugPrint('Launching wallet connect URI: $connectUri');

      final launched = await launchUrl(
        connectUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw 'Could not launch $walletId. Make sure the wallet app is installed.';
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Connects Trust Wallet via WalletConnect v2 (Reown AppKit) and signs in.
  ///
  /// On successful connection, retrieves the wallet address and performs the
  /// same sign-in logic used by the `/onConnect` deep-link route in app_router.dart
  /// (checks walletLinks collection and signs in the user).
  ///
  /// The existing [generateConnectUri] / [decryptConnectResponse] functions
  /// are NOT touched — Trust Wallet uses a separate WC v2 path.
  Future<void> _connectTrustWallet() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // Dispose any stale modal first
    _trustModal?.dispose();
    _trustModal = null;

    try {
      const projectId = '52cb8eaaad34baed8dbe063b454b28f6';

      final modal = await TrustWalletService.createModal(
        context: context,
        projectId: projectId,
      );
      _trustModal = modal;

      // ── Primary: session.future fires when Trust Wallet approves via WC relay ──
      // When the user manually approves in Trust Wallet, the WalletConnect relay
      // delivers the session approval and connectResponse.session.future resolves.
      // onModalConnect only fires when using the built-in modal UI, so we can't
      // rely on it when we manually deep-link into Trust Wallet.

      modal.onModalDisconnect.subscribe((_) {
        modal.onModalDisconnect.unsubscribeAll();
        if (mounted && _isLoading) {
          setState(() => _isLoading = false);
        }
      });

      // Generate the WC v2 connection URI
      if (modal.appKit == null) {
        throw Exception('Reown AppKit client not initialized.');
      }
      final connectResponse = await modal.appKit!.connect(
        optionalNamespaces: modal.optionalNamespaces,
      );

      final wcUri = connectResponse.uri;
      if (wcUri == null) {
        throw Exception('Could not generate WalletConnect URI.');
      }

      // Launch Trust Wallet app with the WC URI
      final encodedUri = Uri.encodeComponent(wcUri.toString());
      final schemes = [
        'trust://wc?uri=$encodedUri',
        'trustwallet://wc?uri=$encodedUri',
        'https://link.trustwallet.com/wc?uri=$encodedUri',
      ];

      bool launched = false;
      for (final scheme in schemes) {
        try {
          final uri = Uri.parse(scheme);
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) {
              debugPrint('Trust Wallet auth: launched via $scheme');
              break;
            }
          }
        } catch (e) {
          debugPrint('Error launching scheme $scheme: $e');
        }
      }

      if (!launched) {
        throw Exception(
          'Could not launch Trust Wallet. Please make sure the app is installed.',
        );
      }

      // Await the WalletConnect session settlement — this is the authoritative
      // callback that fires when Trust Wallet approves the connection request.
      // The session data contains CAIP-10 accounts: "solana:<chainId>:<address>".
      connectResponse.session.future
          .then((sessionData) async {
            debugPrint(
              'Trust Wallet auth session settled: ${sessionData.topic}',
            );

            // Extract the Solana address from the CAIP-10 account string.
            String? address;

            // Try to get it from the settled session's namespaces first.
            final solanaAccounts = sessionData.namespaces['solana']?.accounts;
            if (solanaAccounts != null && solanaAccounts.isNotEmpty) {
              // CAIP-10 format: "solana:<chainId>:<address>"
              final parts = solanaAccounts.first.split(':');
              if (parts.length >= 3) address = parts.last;
            }

            // Fallback: ask the modal for the address (works if modal session is set).
            address ??= modal.session?.getAddress(NetworkUtils.solana);

            debugPrint('Trust Wallet auth: resolved address = $address');

            if (address != null && address.isNotEmpty) {
              if (!mounted) return;
              await _signInWithTrustWalletAddress(address);
            } else {
              debugPrint(
                'Trust Wallet auth: could not extract Solana address.',
              );
              if (mounted) {
                setState(() => _isLoading = false);
                _showError(
                  'Could not retrieve wallet address. Please try again.',
                );
              }
            }
          })
          .catchError((e) {
            debugPrint('Trust Wallet auth connection rejected or failed: $e');
            if (mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Trust Wallet connection failed or rejected.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          });
    } catch (e) {
      _trustModal?.dispose();
      _trustModal = null;
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Trust Wallet connection failed: $e');
      }
    }
  }

  /// Performs the sign-in lookup using the Trust Wallet address.
  ///
  /// Mirrors the "Sign in with Solana Wallet" branch of the `/onConnect`
  /// route handler in app_router.dart. If no linked account exists,
  /// redirects to the register path with the pending pubkey set.
  Future<void> _signInWithTrustWalletAddress(String walletAddress) async {
    final isDarkMode = ref.read(themeModeProvider);
    final firestore = ref.read(firestoreProvider);
    final user = ref.read(userProvider);

    try {
      if (user != null) {
        // User is already logged in — just link the Trust Wallet address
        await firestore.collection('users').doc(user.uid).update({
          'walletPublicKey': walletAddress,
          'connectedWalletType': 'trust',
        });

        final password = await SecureStorageHelper.getPassword();
        final obfuscatedPassword = password != null
            ? SecureStorageHelper.obfuscate(password)
            : null;

        final providers = user.providerData.map((p) => p.providerId).toList();
        final provider = providers.contains('google.com')
            ? 'google.com'
            : 'password';

        final linkData = <String, dynamic>{
          'uid': user.uid,
          'email': user.email,
          'provider': provider,
          'linkedAt': DateTime.now().millisecondsSinceEpoch,
        };
        if (obfuscatedPassword != null) {
          linkData['password'] = obfuscatedPassword;
        }
        await firestore
            .collection('walletLinks')
            .doc(walletAddress)
            .set(linkData);

        ref.invalidate(userProfileProvider);

        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Trust Wallet linked: $walletAddress'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      // Not logged in — look up walletLinks to sign in
      final walletLinkDoc = await firestore
          .collection('walletLinks')
          .doc(walletAddress)
          .get();

      if (!walletLinkDoc.exists) {
        // New wallet — send to register flow
        ref.read(pendingWalletPublicKeyProvider.notifier).state = walletAddress;
        ref.read(authViewProvider.notifier).state = 'register-path';
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Wallet connected! Please register or sign in to link your account.',
              ),
              backgroundColor: Colors.indigo,
            ),
          );
        }
        return;
      }

      final linkData = walletLinkDoc.data();
      var email = linkData?['email'] as String?;
      final uid = linkData?['uid'] as String?;
      final obfuscatedPassword = linkData?['password'] as String?;

      if ((email == null || email.isEmpty) && uid != null) {
        final userDoc = await firestore.collection('users').doc(uid).get();
        email = userDoc.data()?['email'] as String?;
      }

      if (email == null || email.isEmpty) {
        throw 'No email associated with this wallet link.';
      }

      if (obfuscatedPassword != null && obfuscatedPassword.isNotEmpty) {
        final password = SecureStorageHelper.deobfuscate(obfuscatedPassword);
        await ref
            .read(firebaseAuthProvider)
            .signInWithEmailAndPassword(email: email, password: password);

        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logged in successfully via Trust Wallet!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final provider = linkData?['provider'] as String?;

        if (provider == 'google.com') {
          if (mounted) {
            final proceed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) {
                return AlertDialog(
                  backgroundColor: isDarkMode
                      ? AppColors.darkCard
                      : Colors.white,
                  title: Text(
                    'Google Sign-In Required',
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                  content: Text(
                    'This wallet is linked to the Google account $email. Please sign in with Google to authorize this device.',
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Sign in with Google'),
                    ),
                  ],
                );
              },
            );
            if (proceed == true) {
              try {
                await ref.read(authControllerProvider).signInWithGoogle();
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged in successfully via Trust Wallet!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  _showError('Google Sign-In failed: $e');
                }
              }
            } else {
              if (mounted) setState(() => _isLoading = false);
            }
          }
        } else if (provider == 'password') {
          // Prompt user to enter their password to authorize this device
          if (mounted) {
            final password = await _showPasswordPromptDialog(
              context,
              email,
              isDarkMode,
            );
            if (password != null && password.isNotEmpty) {
              await ref
                  .read(firebaseAuthProvider)
                  .signInWithEmailAndPassword(email: email, password: password);

              await SecureStorageHelper.savePassword(password);
              await firestore
                  .collection('walletLinks')
                  .doc(walletAddress)
                  .update({
                    'password': SecureStorageHelper.obfuscate(password),
                  });

              if (mounted) {
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logged in successfully via Trust Wallet!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              if (mounted) setState(() => _isLoading = false);
            }
          }
        } else {
          // Legacy case (provider is null) — show choice dialog
          if (mounted) {
            final choice = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) {
                return AlertDialog(
                  backgroundColor: isDarkMode
                      ? AppColors.darkCard
                      : Colors.white,
                  title: Text(
                    'Authorize Device',
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkText
                          : AppColors.lightText,
                    ),
                  ),
                  content: Text(
                    'This wallet is linked to the email $email. Please choose how you want to authorize this device.',
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('cancel'),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('password'),
                      child: const Text('Use Password'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop('google'),
                      child: const Text('Sign in with Google'),
                    ),
                  ],
                );
              },
            );

            if (choice == 'google') {
              try {
                await ref.read(authControllerProvider).signInWithGoogle();
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged in successfully via Trust Wallet!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  _showError('Google Sign-In failed: $e');
                }
              }
            } else if (choice == 'password') {
              final password = await _showPasswordPromptDialog(
                context,
                email,
                isDarkMode,
              );
              if (password != null && password.isNotEmpty) {
                await ref
                    .read(firebaseAuthProvider)
                    .signInWithEmailAndPassword(
                      email: email,
                      password: password,
                    );

                await SecureStorageHelper.savePassword(password);
                await firestore
                    .collection('walletLinks')
                    .doc(walletAddress)
                    .update({
                      'password': SecureStorageHelper.obfuscate(password),
                    });

                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged in successfully via Trust Wallet!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                if (mounted) setState(() => _isLoading = false);
              }
            } else {
              if (mounted) setState(() => _isLoading = false);
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Trust Wallet Sign-In failed: $e');
      }
    }
  }

  Future<String?> _showPasswordPromptDialog(
    BuildContext context,
    String email,
    bool isDarkMode,
  ) async {
    final controller = TextEditingController();
    bool obscureText = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDarkMode ? AppColors.darkCard : Colors.white,
              title: Text(
                'Authorize Device',
                style: TextStyle(
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter your password for $email to authorize this device with your Trust Wallet.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscureText,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureText ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscureText = !obscureText),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(controller.text.trim()),
                  child: const Text('Authorize'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openStore(String walletId) async {
    final phantomService = ref.read(phantomServiceProvider);
    final storeUrl = phantomService.storeUrlFor(walletId);
    final uri = Uri.parse(storeUrl);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError('Could not open store for $walletId');
      }
    } catch (e) {
      _showError('Could not open store: $e');
    }
  }
}
