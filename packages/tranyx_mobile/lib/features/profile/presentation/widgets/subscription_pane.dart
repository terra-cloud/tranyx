import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/core/services/trust_wallet_service.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';

final rawUserDocProvider =
    StreamProvider.autoDispose<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
      final user = ref.watch(userProvider);
      if (user == null) return Stream.value(null);
      return ref
          .watch(firestoreProvider)
          .collection('users')
          .doc(user.uid)
          .snapshots();
    });

class SubWalletInfo {
  final String id;
  final String name;
  final String scheme;
  final String iosStoreUrl;
  final String androidStoreUrl;
  final String image;

  const SubWalletInfo({
    required this.id,
    required this.name,
    required this.scheme,
    required this.iosStoreUrl,
    required this.androidStoreUrl,
    required this.image,
  });
}

class SubscriptionPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const SubscriptionPane({super.key, required this.onBack});

  @override
  ConsumerState<SubscriptionPane> createState() => _SubscriptionPaneState();
}

class _SubscriptionPaneState extends ConsumerState<SubscriptionPane> {
  bool _isProcessing = false;
  String _selectedPlan = 'monthly'; // 'monthly' | 'yearly'
  double _solToPhpRate = 8000.0;
  bool _isFetchingRate = false;
  double _solBalance = 0.0;
  Timer? _balancePollingTimer;
  String? _lastPolledPubkey;

  // Trust Wallet AppKit modal (kept alive for session requests)
  ReownAppKitModal? _trustModal;

  // Wallet list matching payment_pane
  final List<SubWalletInfo> wallets = const [
    SubWalletInfo(
      id: 'phantom',
      name: 'Phantom',
      scheme: 'phantom://',
      iosStoreUrl: 'https://apps.apple.com/app/phantom-solana-wallet/id1598432977',
      androidStoreUrl: 'https://play.google.com/store/apps/details?id=app.phantom',
      image: 'assets/images/PhantomWallet.png',
    ),
    SubWalletInfo(
      id: 'solflare',
      name: 'Solflare',
      scheme: 'solflare://',
      iosStoreUrl: 'https://apps.apple.com/app/solflare-solana-wallet/id1580902717',
      androidStoreUrl: 'https://play.google.com/store/apps/details?id=com.solflare.mobile',
      image: 'assets/images/Solflare.png',
    ),
    SubWalletInfo(
      id: 'trust',
      name: 'Trust Wallet',
      scheme: 'trust://',
      iosStoreUrl: 'https://apps.apple.com/app/trust-crypto-bitcoin-wallet/id1288339409',
      androidStoreUrl: 'https://play.google.com/store/apps/details?id=com.wallet.crypto.trustapp',
      image: 'assets/images/TrustWallet.jpeg',
    ),
  ];

  Map<String, bool> _installedWallets = {};

  @override
  void initState() {
    super.initState();
    _checkInstalledWallets();
    _fetchRates();
  }

  @override
  void dispose() {
    _trustModal?.dispose();
    _stopBalancePolling();
    super.dispose();
  }

  Future<void> _fetchRates() async {
    if (!mounted) return;
    setState(() => _isFetchingRate = true);
    try {
      final cgRes = await http.get(
        Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=php'),
      );
      if (cgRes.statusCode == 200) {
        final data = jsonDecode(cgRes.body) as Map<String, dynamic>;
        final sol = (data['solana']?['php'] as num?)?.toDouble();
        if (mounted && sol != null && sol > 0) {
          setState(() {
            _solToPhpRate = sol;
          });
        }
      }
    } catch (_) {
      // Use fallback silently
    } finally {
      if (mounted) setState(() => _isFetchingRate = false);
    }
  }

  Future<void> _fetchSolBalance(String pubkey) async {
    try {
      final rpcUrl = ref.read(phantomServiceProvider).rpcUrl;
      final solRes = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getBalance',
          'params': [pubkey],
        }),
      );
      if (solRes.statusCode == 200) {
        final data = jsonDecode(solRes.body);
        final lamports = (data['result']?['value'] as num?)?.toDouble() ?? 0.0;
        if (mounted) setState(() => _solBalance = lamports / 1e9);
      }
    } catch (_) {}
  }

  void _checkInstalledWallets() async {
    final Map<String, bool> status = {};
    for (final wallet in wallets) {
      bool installed = false;
      List<String> schemesToCheck = [wallet.scheme];

      if (wallet.id == 'trust') {
        schemesToCheck = [
          'trust://wc',
          'trustwallet://wc',
          'trust://open_url',
          'trustwallet://open_url',
          'trust://',
          'trustwallet://',
        ];
      } else if (wallet.id == 'phantom') {
        schemesToCheck = ['phantom://', 'phantom://v1/connect'];
      } else if (wallet.id == 'solflare') {
        schemesToCheck = ['solflare://', 'solflare://ul/v1/connect', 'solflare://v1/connect'];
      }

      for (final scheme in schemesToCheck) {
        try {
          final uri = Uri.parse(scheme);
          if (await canLaunchUrl(uri)) {
            installed = true;
            break;
          }
        } catch (_) {}
      }
      status[wallet.id] = installed;
    }
    if (mounted) {
      setState(() {
        _installedWallets = status;
      });
    }
  }

  void _startBalancePolling(String pubkey) {
    if (_lastPolledPubkey == pubkey && _balancePollingTimer?.isActive == true) {
      return;
    }
    _stopBalancePolling();
    _lastPolledPubkey = pubkey;
    _fetchSolBalance(pubkey);
    _balancePollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchSolBalance(pubkey),
    );
  }

  void _stopBalancePolling() {
    _balancePollingTimer?.cancel();
    _balancePollingTimer = null;
    _lastPolledPubkey = null;
  }

  Future<void> _handleConnectWallet(String uid, SubWalletInfo wallet) async {
    if (wallet.id == 'trust') {
      await _handleConnectTrustWallet(uid);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final phantomService = ref.read(phantomServiceProvider);
      final connectUri = await phantomService.generateConnectUri(
        walletType: wallet.id,
      );
      final launched = await launchUrl(
        connectUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw 'Could not launch wallet application. Make sure the wallet app is installed.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleConnectTrustWallet(String uid) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    _trustModal?.dispose();
    _trustModal = null;

    try {
      const projectId = '52cb8eaaad34baed8dbe063b454b28f6';
      final modal = await TrustWalletService.createModal(
        context: context,
        projectId: projectId,
      );
      _trustModal = modal;

      modal.appKit?.onSessionUpdate.subscribe((SessionUpdate? args) async {
        final address = modal.session?.getAddress(NetworkUtils.solana);
        if (address != null && address.isNotEmpty) {
          await _handleMobileAccountChanged(address);
        }
      });

      modal.appKit?.onSessionDelete.subscribe((SessionDelete? args) async {
        await _handleMobileDisconnect();
      });

      modal.onModalConnect.subscribe((ModalConnect? event) async {
        modal.onModalConnect.unsubscribeAll();
        final address = modal.session?.getAddress(NetworkUtils.solana);
        if (address != null && address.isNotEmpty) {
          final user = ref.read(userProvider);
          if (user != null && mounted) {
            try {
              final existingDoc = await ref
                  .read(firestoreProvider)
                  .collection('walletLinks')
                  .doc(address)
                  .get();

              if (existingDoc.exists) {
                final existingUid = existingDoc.data()?['uid'] as String?;
                if (existingUid != null && existingUid != user.uid) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This wallet is already linked to another account.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    setState(() => _isProcessing = false);
                  }
                  return;
                }
              }

              await ref
                  .read(firestoreProvider)
                  .collection('users')
                  .doc(user.uid)
                  .update({
                'walletPublicKey': address,
                'connectedWalletType': 'trust',
              });

              final password = await SecureStorageHelper.getPassword();
              final obfuscatedPassword = password != null
                  ? SecureStorageHelper.obfuscate(password)
                  : null;
              final linkData = <String, dynamic>{
                'uid': user.uid,
                'email': user.email,
                'linkedAt': DateTime.now().millisecondsSinceEpoch,
              };
              if (obfuscatedPassword != null) {
                linkData['password'] = obfuscatedPassword;
              }
              await ref
                  .read(firestoreProvider)
                  .collection('walletLinks')
                  .doc(address)
                  .set(linkData);

              ref.invalidate(userProfileProvider);
              if (mounted) {
                setState(() => _isProcessing = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Trust Wallet connected: $address'), backgroundColor: Colors.green),
                );
              }
            } catch (e) {
              if (mounted) {
                setState(() => _isProcessing = false);
              }
            }
          }
        }
      });

      if (modal.appKit == null) throw Exception('Reown AppKit client not initialized.');
      final connectResponse = await modal.appKit!.connect(
        optionalNamespaces: modal.optionalNamespaces,
      );

      final wcUri = connectResponse.uri;
      if (wcUri == null) throw Exception('Could not generate WalletConnect URI.');

      final encodedUri = Uri.encodeComponent(wcUri.toString());
      final schemes = [
        'trust://wc?uri=$encodedUri',
        'trustwallet://wc?uri=$encodedUri',
      ];

      bool launched = false;
      for (final scheme in schemes) {
        try {
          final uri = Uri.parse(scheme);
          if (await canLaunchUrl(uri)) {
            launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (launched) break;
          }
        } catch (_) {}
      }

      if (!launched) throw Exception('Could not launch Trust Wallet.');
    } catch (e) {
      _trustModal?.dispose();
      _trustModal = null;
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleMobileAccountChanged(String address) async {
    ref.invalidate(userProfileProvider);
  }

  Future<void> _handleMobileDisconnect() async {
    ref.invalidate(userProfileProvider);
  }

  Future<void> _handleSubscribe({
    required String uid,
    required double phpAmount,
    required double cryptoAmount,
    required String walletType,
    required String userPubkey,
  }) async {
    setState(() => _isProcessing = true);

    try {
      final firestore = ref.read(firestoreProvider);
      final configDoc = await firestore
          .collection('system_config')
          .doc('treasury')
          .get();
      final treasuryPublicKey = configDoc.data()?['publicKey'] as String?;

      if (treasuryPublicKey == null || treasuryPublicKey.isEmpty) {
        throw Exception('Treasury wallet is not configured.');
      }

      if (walletType == 'trust') {
        // Trust Wallet flow
        await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
        await SecureStorageHelper.savePendingDepositCryptoAmount(cryptoAmount);
        await SecureStorageHelper.savePendingDepositCurrency('SOL');
        await SecureStorageHelper.savePendingAction('subscription');
        await SecureStorageHelper.savePendingSubscriptionType(_selectedPlan);

        final modal = _trustModal;
        if (modal == null || !modal.isConnected || modal.session == null) {
          throw Exception('No active Trust Wallet session. Please reconnect.');
        }

        final phantomService = ref.read(phantomServiceProvider);
        final blockhash = await phantomService.fetchRecentBlockhash();
        final lamports = (cryptoAmount * 1e9).round();
        final txBytes = phantomService.serializeTransferTransaction(
          senderPubkey: userPubkey,
          receiverPubkey: treasuryPublicKey,
          blockhash: blockhash,
          lamports: lamports,
        );

        await phantomService.simulateTransaction(base58.encode(txBytes));
        final base64Tx = base64.encode(txBytes);
        final chainId = TrustWalletService.getSolanaChainId();

        final requestFuture = modal.request(
          topic: modal.session!.topic,
          chainId: chainId,
          request: SessionRequestParams(
            method: 'solana_signTransaction',
            params: {'transaction': base64Tx},
          ),
        );

        final schemes = ['trust://', 'trustwallet://'];
        bool launched = false;
        for (final scheme in schemes) {
          try {
            final uri = Uri.parse(scheme);
            if (await canLaunchUrl(uri)) {
              launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (launched) break;
            }
          } catch (_) {}
        }

        final result = await requestFuture;
        String txSignature;
        if (result is Map) {
          final sig = result['signature'] as String? ?? result['transaction'] as String?;
          if (sig == null || sig.isEmpty) throw Exception('Empty signature returned.');
          txSignature = await ref.read(phantomServiceProvider).sendTransaction(sig);
        } else if (result is String) {
          txSignature = await ref.read(phantomServiceProvider).sendTransaction(result);
        } else {
          throw Exception('Unexpected response.');
        }

        final confirmed = await ref.read(phantomServiceProvider).confirmTransaction(txSignature);
        if (!confirmed) throw Exception('Transaction broadcasted but not confirmed.');

        // Success inside client
        await SecureStorageHelper.deletePendingDepositPhpAmount();
        await SecureStorageHelper.deletePendingDepositCryptoAmount();
        await SecureStorageHelper.deletePendingDepositCurrency();
        await SecureStorageHelper.deletePendingAction();
        await SecureStorageHelper.deletePendingSubscriptionType();

        final now = DateTime.now();
        final premiumUntil = _selectedPlan == 'yearly'
            ? now.add(const Duration(days: 365))
            : now.add(const Duration(days: 30));

        await firestore.collection('users').doc(uid).update({
          'isPremium': true,
          'premiumUntil': premiumUntil.millisecondsSinceEpoch,
          'accountType': 'hybrid',
        });

        final txId = 'sub_sol_$txSignature';
        await firestore.collection('transactions').doc(txId).set({
          'uid': uid,
          'type': 'subscription',
          'amount': phpAmount,
          'title': 'Hybrid PRO Subscription (${_selectedPlan == 'yearly' ? 'Yearly' : 'Monthly'})',
          'desc': 'Subscribed via Trust Wallet (${cryptoAmount.toStringAsFixed(4)} SOL)',
          'method': 'Trust Wallet',
          'solanaTxSignature': txSignature,
          'createdAt': now.millisecondsSinceEpoch,
        });

        ref.invalidate(userProfileProvider);
        ref.invalidate(userTransactionsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully subscribed to Hybrid PRO (${_selectedPlan == 'yearly' ? 'Yearly' : 'Monthly'})!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Phantom/Solflare flow (Deep Link)
        await SecureStorageHelper.savePendingDepositPhpAmount(phpAmount);
        await SecureStorageHelper.savePendingDepositCryptoAmount(cryptoAmount);
        await SecureStorageHelper.savePendingDepositCurrency('SOL');
        await SecureStorageHelper.savePendingAction('subscription');
        await SecureStorageHelper.savePendingSubscriptionType(_selectedPlan);

        final phantomService = ref.read(phantomServiceProvider);
        final signUri = await phantomService.generateSignTransactionUri(
          walletType: walletType,
          senderPubkey: userPubkey,
          receiverPubkey: treasuryPublicKey,
          amountInSol: cryptoAmount,
        );

        final launched = await launchUrl(
          signUri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) throw 'Could not launch wallet app.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showWalletConnectModal(String uid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDarkMode = ref.read(themeModeProvider);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connect Solana Wallet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a wallet to connect for your subscription.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ...wallets.map((wallet) {
                final isInstalled = _installedWallets[wallet.id] ?? false;
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(wallet.image, width: 32, height: 32, fit: BoxFit.cover),
                  ),
                  title: Text(wallet.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isInstalled ? 'Installed' : 'App Store / Play Store'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    if (isInstalled) {
                      _handleConnectWallet(uid, wallet);
                    } else {
                      launchUrl(Uri.parse(ref.read(phantomServiceProvider).storeUrlFor(wallet.id)));
                    }
                  },
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final rawUserDoc = ref.watch(rawUserDocProvider).value;

    final backgroundGradient = isDarkMode
        ? const LinearGradient(
            colors: [Color(0xFF0F0C20), Color(0xFF15102A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFF5F5FA), Color(0xFFEAEAFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    final cardColor = isDarkMode ? const Color(0xFF1E193C) : Colors.white;
    final borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);

    return userProfileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
      data: (profile) {
        if (profile == null) return const Center(child: Text('User profile not loaded.'));

        final hasWallet = profile.walletPublicKey != null && profile.walletPublicKey!.isNotEmpty;
        final connectedWalletType = rawUserDoc?.data()?['connectedWalletType'] as String? ?? (hasWallet ? 'phantom' : null);

        if (hasWallet) {
          _startBalancePolling(profile.walletPublicKey!);
        } else {
          _stopBalancePolling();
        }

        final double phpPrice = _selectedPlan == 'yearly' ? 2999.0 : 299.0;
        final double solPrice = phpPrice / _solToPhpRate;

        return Container(
          decoration: BoxDecoration(gradient: backgroundGradient),
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.white : Colors.black87),
                          onPressed: widget.onBack,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Hybrid PRO Upgrade',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          // Banner / Intro Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                                    SizedBox(width: 8),
                                    Text(
                                      'TRANYX HYBRID PRO',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Unlock All PRO Features',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Dual Nyxian & Employer permissions, priority search exposure, reduced service fees, and unlimited messaging tools.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Plan Selection Header
                          Text(
                            'Select Subscription Plan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Plan cards side-by-side or stacked
                          Row(
                            children: [
                              // 1 Month Sub Card
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedPlan = 'monthly'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: _selectedPlan == 'monthly'
                                          ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                                          : cardColor,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _selectedPlan == 'monthly'
                                            ? const Color(0xFF6366F1)
                                            : borderColor,
                                        width: _selectedPlan == 'monthly' ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          '1 Month',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '◎ ${(299.0 / _solToPhpRate).toStringAsFixed(4)} SOL',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF6366F1),
                                          ),
                                        ),
                                        const Text(
                                          '₱299 PHP basis',
                                          style: TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // 1 Year Sub Card (with 16% savings)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedPlan = 'yearly'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: _selectedPlan == 'yearly'
                                          ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                                          : cardColor,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _selectedPlan == 'yearly'
                                            ? const Color(0xFF6366F1)
                                            : borderColor,
                                        width: _selectedPlan == 'yearly' ? 2 : 1,
                                      ),
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Column(
                                          children: [
                                            Text(
                                              '1 Year',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isDarkMode ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              '◎ ${(2999.0 / _solToPhpRate).toStringAsFixed(4)} SOL',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF6366F1),
                                              ),
                                            ),
                                            const Text(
                                              '₱2,999 PHP basis',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 11, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                        Positioned(
                                          top: -30,
                                          right: -8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              '16% SAVED',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Comparison section on mobile
                          const SizedBox(height: 24),
                          Text(
                            'Compare Plans',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Lite Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 4.5,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.grey,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Lite',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Basic account with a single active role',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const Divider(height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      'Single',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: isDarkMode ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Choose either Nyxian or Employer role',
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _perkRow('Single account role active at a time', isDarkMode),
                                _perkRow('Standard search exposure ranking', isDarkMode),
                                _perkRow('Standard 3% platform service fee', isDarkMode),
                                _perkRow('Limited daily messaging tools', isDarkMode),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Pro Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _selectedPlan == 'monthly'
                                  ? const Color(0xFF6366F1).withValues(alpha: 0.05)
                                  : const Color(0xFF6366F1).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 4.5,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Pro 🔥',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'RECOMMENDED',
                                        style: TextStyle(
                                          color: Color(0xFF6366F1),
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Unlock full Hybrid permissions & tools 🔥',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const Divider(height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    const Text(
                                      'Hybrid',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Simultaneously hire and work with no friction',
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _perkRow('Dual Nyxian & Employer permissions', isDarkMode),
                                _perkRow('Priority search & listing exposure', isDarkMode),
                                _perkRow('Reduced service fee (1.5% platform cut)', isDarkMode),
                                _perkRow('Unlimited client/employer messages', isDarkMode),
                                _perkRow('Premium Hybrid profile badge', isDarkMode),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Realtime Crypto Pricing Details
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Payment Method', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                    Text('Solana Crypto Wallet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Text('SOL Price (Real-time)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: _isFetchingRate ? null : _fetchRates,
                                          child: _isFetchingRate
                                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                                              : Icon(Icons.refresh, size: 16, color: isDarkMode ? Colors.white70 : Colors.black54),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '1 SOL = ₱${_solToPhpRate.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '◎ ${solPrice.toStringAsFixed(5)} SOL',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF6366F1),
                                          ),
                                        ),
                                        Text(
                                          '₱${phpPrice.toStringAsFixed(2)} PHP',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Wallet connection pane
                          if (!hasWallet) ...[
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 40),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No Crypto Wallet Connected',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'A Solana wallet is required to pay for your Hybrid PRO subscription with SOL.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    onPressed: () => _showWalletConnectModal(profile.uid),
                                    child: const Text('Connect Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet_outlined, color: isDarkMode ? Colors.white70 : Colors.black54),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Connected ${connectedWalletType?.toUpperCase() ?? 'Wallet'}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              profile.walletPublicKey!.length > 15
                                                  ? '${profile.walletPublicKey!.substring(0, 8)}...${profile.walletPublicKey!.substring(profile.walletPublicKey!.length - 8)}'
                                                  : profile.walletPublicKey!,
                                              style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Wallet SOL Balance', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      Text(
                                        '${_solBalance.toStringAsFixed(4)} SOL',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _solBalance < solPrice ? Colors.red : Colors.green),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Action CTA button
                            _isProcessing
                                ? const Center(child: CircularProgressIndicator())
                                : SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _solBalance < solPrice ? Colors.grey : const Color(0xFF6366F1),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        elevation: 0,
                                      ),
                                      onPressed: _solBalance < solPrice
                                          ? null
                                          : () => _handleSubscribe(
                                                uid: profile.uid,
                                                phpAmount: phpPrice,
                                                cryptoAmount: solPrice,
                                                walletType: connectedWalletType ?? 'phantom',
                                                userPubkey: profile.walletPublicKey!,
                                              ),
                                      child: Text(
                                        _solBalance < solPrice
                                            ? 'Insufficient SOL Balance'
                                            : 'Pay ${solPrice.toStringAsFixed(4)} SOL & Activate PRO',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                    ),
                                  ),
                          ],

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              );
      },
    );
  }

  Widget _perkRow(String text, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
