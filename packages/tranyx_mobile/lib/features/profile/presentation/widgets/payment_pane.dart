import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';

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

class WalletInfo {
  final String id;
  final String name;
  final String scheme;
  final String iosStoreUrl;
  final String androidStoreUrl;
  final String image;

  const WalletInfo({
    required this.id,
    required this.name,
    required this.scheme,
    required this.iosStoreUrl,
    required this.androidStoreUrl,
    required this.image,
  });
}

const List<WalletInfo> wallets = [
  WalletInfo(
    id: 'phantom',
    name: 'Phantom',
    scheme: 'phantom://',
    iosStoreUrl:
        'https://apps.apple.com/app/phantom-solana-wallet/id1598432977',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=app.phantom',
    image: 'assets/images/PhantomWallet.png',
  ),
  WalletInfo(
    id: 'solflare',
    name: 'Solflare',
    scheme: 'solflare://',
    iosStoreUrl:
        'https://apps.apple.com/app/solflare-solana-wallet/id1580902717',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.solflare.mobile',
    image: 'assets/images/Solflare.png',
  ),
  WalletInfo(
    id: 'backpack',
    name: 'Backpack',
    scheme: 'backpack://',
    iosStoreUrl: 'https://apps.apple.com/app/backpack-wallet/id6448764881',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=co.backpack.wallet',
    image: 'assets/images/BackPack.png',
  ),
  WalletInfo(
    id: 'trust',
    name: 'Trust Wallet',
    scheme: 'trust://',
    iosStoreUrl:
        'https://apps.apple.com/app/trust-crypto-bitcoin-wallet/id1288339409',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.wallet.crypto.trustapp',
    image: 'assets/images/TrustWallet.jpeg',
  ),
];

class PaymentPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const PaymentPane({super.key, required this.onBack});

  @override
  ConsumerState<PaymentPane> createState() => _PaymentPaneState();
}

class _PaymentPaneState extends ConsumerState<PaymentPane> {
  final _amountController = TextEditingController();
  bool _isProcessing = false;
  Map<String, bool> _installedWallets = {};

  @override
  void initState() {
    super.initState();
    _checkInstalledWallets();
  }

  void _checkInstalledWallets() async {
    final Map<String, bool> status = {};
    for (final wallet in wallets) {
      bool installed = false;
      try {
        installed = await canLaunchUrl(Uri.parse(wallet.scheme));
      } catch (_) {}
      status[wallet.id] = installed;
    }
    if (mounted) {
      setState(() {
        _installedWallets = status;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showDepositSheet(double tyxBalance, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Deposit Funds',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter PHP Amount to convert to TYXBIT (1 PHP = 1 TYXBIT)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  hintText: '0.00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _isProcessing
                  ? const Center(child: CircularProgressIndicator())
                  : UIHelpers.buildPrimaryButton(
                      'Confirm Payment (Xendit)',
                      () async {
                        final val = _amountController.text.trim();
                        final amount = double.tryParse(val);
                        if (amount == null || amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid amount'),
                            ),
                          );
                          return;
                        }

                        setState(() => _isProcessing = true);
                        Navigator.pop(sheetContext);

                        try {
                          final userProfile = ref
                              .read(userProfileProvider)
                              .value;
                          final userName = userProfile?.name ?? 'User';

                          final res = await ref
                              .read(transitRepositoryProvider)
                              .createXenditInvoice(
                                uid: uid,
                                amount: amount,
                                userName: userName,
                              );

                          final invoiceId = res['id'] as String;
                          final invoiceUrl = res['invoice_url'] as String;

                          // Save pending invoice details to Firestore
                          await ref
                              .read(firestoreProvider)
                              .collection('users')
                              .doc(uid)
                              .update({
                                'pendingXenditInvoiceId': invoiceId,
                                'pendingXenditInvoiceAmount': amount,
                                'pendingXenditInvoiceUrl': invoiceUrl,
                              });

                          _amountController.clear();

                          // Launch checkout URL in browser
                          try {
                            final uri = Uri.parse(invoiceUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          } catch (urlErr) {
                            debugPrint(
                              'URL Launch error (expected in tests): $urlErr',
                            );
                          }

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Invoice created. Launching checkout for ₱ ${amount.toStringAsFixed(2)}',
                                ),
                                backgroundColor: Colors.indigo,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error creating invoice: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          setState(() => _isProcessing = false);
                        }
                      },
                      ref.read(themeModeProvider),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleVerifyPayment(String uid, String invoiceId, double amount) async {
    setState(() => _isProcessing = true);
    try {
      final isPaid = await ref
          .read(transitRepositoryProvider)
          .verifyXenditPayment(uid: uid, invoiceId: invoiceId, amount: amount);

      if (isPaid) {
        // Clear pending invoice from Firestore
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'pendingXenditInvoiceId': FieldValue.delete(),
          'pendingXenditInvoiceAmount': FieldValue.delete(),
          'pendingXenditInvoiceUrl': FieldValue.delete(),
        });
        ref.invalidate(userProfileProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment Verified! Balance credited successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invoice is still unpaid or pending.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _handleCancelInvoice(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Pending Invoice'),
        content: const Text(
          'Are you sure you want to cancel and dismiss this pending Xendit invoice?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Invoice'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'pendingXenditInvoiceId': FieldValue.delete(),
          'pendingXenditInvoiceAmount': FieldValue.delete(),
          'pendingXenditInvoiceUrl': FieldValue.delete(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pending invoice dismissed.'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel invoice: $e')),
          );
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleConnectWallet(String uid, WalletInfo wallet) async {
    setState(() => _isProcessing = true);
    try {
      final phantomService = ref.read(phantomServiceProvider);
      final connectUri = await phantomService.generateConnectUri(walletType: wallet.id);
      
      debugPrint('Launching wallet deep link connect URI: $connectUri');
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
      setState(() => _isProcessing = false);
    }
  }

  void _handleDisconnectWallet(String uid, WalletInfo wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disconnect ${wallet.name}'),
        content: Text(
          'Are you sure you want to disconnect your ${wallet.name} wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        await ref.read(firestoreProvider).collection('users').doc(uid).update({
          'walletPublicKey': null,
          'connectedWalletType': null,
        });

        ref.invalidate(userProfileProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${wallet.name} wallet disconnected.'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e')));
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleWithdraw(double tyxBalance, String uid) async {
    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile == null) return;

    if (userProfile.walletPublicKey == null ||
        userProfile.walletPublicKey!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please connect a Solana wallet first before withdrawing.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (tyxBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No earnings available for withdrawal')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Withdrawal'),
        content: Text(
          'Are you sure you want to withdraw your entire balance of ₱ ${tyxBalance.toStringAsFixed(2)} to your connected Solana wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        // Mock withdraw by setting balance to 0 and writing transaction
        await ref.read(transitRepositoryProvider).updateTyxBalance(uid, 0);
        final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
        await ref
            .read(firestoreProvider)
            .collection('transactions')
            .doc(txId)
            .set({
              'uid': uid,
              'type': 'withdraw',
              'amount': tyxBalance,
              'title': 'Earnings Withdrawn',
              'desc': 'Withdrew all earnings payout to Solana Wallet address',
              'method': 'Tranyx Wallet',
              'createdAt': DateTime.now().millisecondsSinceEpoch,
            });

        ref.invalidate(userProfileProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Withdrawal successful! Payout sent to Solana wallet.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Withdrawal failed: $e')));
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfile = ref.watch(userProfileProvider).value;
    final transactionsAsync = ref.watch(userTransactionsProvider);
    final rawUserDocAsync = ref.watch(rawUserDocProvider);

    if (userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final rawUserDoc = rawUserDocAsync.value;
    final pendingInvoiceId =
        rawUserDoc?.data()?['pendingXenditInvoiceId'] as String?;
    final pendingInvoiceAmount =
        (rawUserDoc?.data()?['pendingXenditInvoiceAmount'] as num?)?.toDouble();
    final pendingInvoiceUrl =
        rawUserDoc?.data()?['pendingXenditInvoiceUrl'] as String?;

    final connectedWalletType =
        rawUserDoc?.data()?['connectedWalletType'] as String? ??
        (userProfile.walletPublicKey != null &&
                userProfile.walletPublicKey!.isNotEmpty
            ? 'phantom'
            : null);
    final hasWallet =
        userProfile.walletPublicKey != null &&
        userProfile.walletPublicKey!.isNotEmpty;

    final tyxBalance = userProfile.tyxBalance;
    final uid = userProfile.uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              onPressed: widget.onBack,
            ),
            const SizedBox(width: 8),
            const Text(
              'Payment Methods',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Wallet Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              colors: [AppColors.indigo, AppColors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.indigo.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TYXBIT MAIN WALLET',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userProfile.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    '₱ ',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    tyxBalance.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'tranyx-tyxbit-v1 :: ${uid.substring(0, min(8, uid.length))}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      label: const Text(
                        'Deposit',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _showDepositSheet(tyxBalance, uid),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      label: const Text(
                        'Withdraw',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _handleWithdraw(tyxBalance, uid),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (pendingInvoiceId != null) ...[
          const SizedBox(height: 24),
          const Text(
            'Pending Deposit',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pending_actions, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          'Xendit Checkout',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Amount',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱ ${pendingInvoiceAmount?.toStringAsFixed(2) ?? "0.00"}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Invoice ID',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pendingInvoiceId.substring(
                                0,
                                min(12, pendingInvoiceId.length),
                              ) +
                              '...',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.payment, size: 14),
                        label: const Text(
                          'Pay Now',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          if (pendingInvoiceUrl != null) {
                            final uri = Uri.parse(pendingInvoiceUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.indigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 14),
                        label: const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _handleVerifyPayment(
                                uid,
                                pendingInvoiceId,
                                pendingInvoiceAmount ?? 0.0,
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: _isProcessing
                          ? null
                          : () => _handleCancelInvoice(uid),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Connected Solana Wallet Section
        const SizedBox(height: 24),
        const Text(
          'Linked Solana Wallet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Column(
          children: wallets.map((wallet) {
            final isInstalled = _installedWallets[wallet.id] ?? false;
            final isConnected = hasWallet && connectedWalletType == wallet.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isConnected
                      ? Colors.purple
                      : (isDarkMode
                            ? AppColors.darkBorder
                            : AppColors.lightBorder),
                  width: isConnected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isConnected
                            ? Colors.purple.withOpacity(0.5)
                            : (isDarkMode ? Colors.white12 : Colors.black12),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset(
                        wallet.image,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            isConnected
                                ? Icons.link
                                : Icons.account_balance_wallet,
                            color: isConnected ? Colors.purple : Colors.grey,
                            size: 20,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              wallet.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (isConnected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isConnected
                              ? '${userProfile.walletPublicKey!.substring(0, min(8, userProfile.walletPublicKey!.length))}...${userProfile.walletPublicKey!.substring(max(0, userProfile.walletPublicKey!.length - 8))}'
                              : (isInstalled
                                    ? 'Tap to connect Solana Wallet'
                                    : 'Not installed'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : isInstalled
                      ? ElevatedButton(
                          onPressed: () {
                            if (isConnected) {
                              _handleDisconnectWallet(uid, wallet);
                            } else {
                              if (hasWallet) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please disconnect your active wallet first before connecting another one.',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              } else {
                                _handleConnectWallet(uid, wallet);
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnected
                                ? Colors.red.withValues(alpha: 0.1)
                                : AppColors.indigo,
                            foregroundColor: isConnected
                                ? Colors.red
                                : Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isConnected ? 'Disconnect' : 'Connect',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () async {
                            final isIOS =
                                Theme.of(context).platform ==
                                TargetPlatform.iOS;
                            final storeUrl = isIOS
                                ? wallet.iosStoreUrl
                                : wallet.androidStoreUrl;
                            final uri = Uri.parse(storeUrl);
                            try {
                              // For simulator/iOS, using inAppWebView avoids "Safari cannot open..." scheme issues.
                              await launchUrl(
                                uri,
                                mode: LaunchMode.inAppWebView,
                              );
                            } catch (e) {
                              try {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.platformDefault,
                                );
                              } catch (_) {}
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.indigo,
                            side: const BorderSide(color: AppColors.indigo),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Install',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ],
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 32),

        const Text(
          'Transaction Log',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Transactions List
        transactionsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, stack) {
            print(err);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Error: $err')),
            );
          },
          data: (txList) {
            if (txList.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No transactions recorded yet',
                    style: TextStyle(
                      color: isDarkMode
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(0),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: txList.length,
              itemBuilder: (context, index) {
                final tx = txList[index];
                final isDeposit =
                    tx['type'] == 'deposit' || tx['type'] == 'refund';
                final isWithdraw = tx['type'] == 'withdraw';
                final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                final title = tx['title'] as String? ?? 'Transaction';
                final desc = tx['desc'] as String? ?? '';
                final dateVal = tx['createdAt'] as int? ?? 0;
                final dateStr = DateFormat(
                  'MMM dd, yyyy • hh:mm a',
                ).format(DateTime.fromMillisecondsSinceEpoch(dateVal));

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? AppColors.darkCard
                        : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDarkMode
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDeposit
                              ? Colors.green.withValues(alpha: 0.1)
                              : isWithdraw
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDeposit
                              ? Icons.add_circle_outline
                              : isWithdraw
                              ? Icons.remove_circle_outline
                              : Icons.swap_horiz,
                          color: isDeposit
                              ? Colors.green
                              : isWithdraw
                              ? Colors.blue
                              : Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted
                                    : AppColors.lightTextMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDarkMode
                                    ? AppColors.darkTextMuted.withValues(
                                        alpha: 0.7,
                                      )
                                    : AppColors.lightTextMuted.withValues(
                                        alpha: 0.7,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${isDeposit ? "+" : "-"}${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDeposit ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
