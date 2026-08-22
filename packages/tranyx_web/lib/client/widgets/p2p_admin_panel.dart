import 'dart:async';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class P2pAdminPanelComponent extends StatefulComponent {
  final TranyxAppState state;

  const P2pAdminPanelComponent({required this.state, super.key});

  @override
  State<P2pAdminPanelComponent> createState() => _P2pAdminPanelComponentState();
}

class _P2pAdminPanelComponentState extends State<P2pAdminPanelComponent> {
  String _activeTab = 'queue'; // 'queue' or 'settings'
  String _statusFilter = 'ALL'; // 'ALL', 'WAITING_FOR_AGENT', 'PENDING_VERIFICATION', 'AWAITING_PAYMENT', 'APPROVED', 'REJECTED'
  String _searchQuery = '';
  String? _previewImageUrl;
  String? _rejectingDepositId;
  String _rejectionReason = '';
  bool _isLoading = false;
  Timer? _pollTimer;
  int _lastKnownWaitingCount = 0;

  // Agent form state
  late String _agentName;
  late String _agentPhone;
  late String _agentEmail;
  late bool _isActive;
  late String _gcashAccountName;
  late String _gcashNumber;
  late String _gcashQrUrl;
  late String _mayaAccountName;
  late String _mayaNumber;
  late String _mayaQrUrl;

  @override
  void initState() {
    super.initState();
    _initAgentForm();
    _loadRequests();

    // Start Real-time Queue Polling & Audio Dispatch Listener
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await component.state.loadP2pAdminData();
      final currentWaiting = component.state.pendingDepositRequests
          .where((r) => r.status.toUpperCase() == 'WAITING_FOR_AGENT')
          .length;
      if (currentWaiting > _lastKnownWaitingCount && _lastKnownWaitingCount >= 0) {
        _playChime();
        component.state.showAppToast(
          'Incoming P2P Top-up!',
          'A user requested a payment QR code. Claim the order below.',
        );
      }
      _lastKnownWaitingCount = currentWaiting;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _playChime() {
    try {
      final audioCtx = web.AudioContext();
      final osc = audioCtx.createOscillator();
      final gain = audioCtx.createGain();
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.frequency.setValueAtTime(587.33, audioCtx.currentTime); // D5
      osc.frequency.setValueAtTime(880.0, audioCtx.currentTime + 0.12); // A5
      gain.gain.setValueAtTime(0.15, audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.4);
      osc.start();
      osc.stop(audioCtx.currentTime + 0.4);
    } catch (_) {}
  }

  void _initAgentForm() {
    final agent = component.state.activeP2pAgent;
    _agentName = agent.name;
    _agentPhone = agent.phone;
    _agentEmail = agent.email;
    _isActive = agent.isActive;
    _gcashAccountName = agent.gcashAccountName;
    _gcashNumber = agent.gcashNumber;
    _gcashQrUrl = agent.gcashQrUrl;
    _mayaAccountName = agent.mayaAccountName;
    _mayaNumber = agent.mayaNumber;
    _mayaQrUrl = agent.mayaQrUrl;
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    await component.state.loadP2pAdminData();
    setState(() => _isLoading = false);
  }

  Future<void> _handleApprove(DepositRequest req) async {
    setState(() => _isLoading = true);
    try {
      await component.state.handleApproveDepositRequest(req.id);
      component.state.showAppToast(
        'Deposit Approved',
        '₱${req.amount.toStringAsFixed(2)} has been credited to ${req.userName}\'s balance.',
      );
    } catch (e) {
      component.state.alertDialog('Approval Failed', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRejectSubmit() async {
    if (_rejectingDepositId == null) return;
    final reason = _rejectionReason.trim().isEmpty ? 'Payment reference could not be verified' : _rejectionReason.trim();

    setState(() => _isLoading = true);
    try {
      await component.state.handleRejectDepositRequest(_rejectingDepositId!, reason);
      component.state.showAppToast('Deposit Rejected', 'The deposit request was marked as rejected.');
      setState(() {
        _rejectingDepositId = null;
        _rejectionReason = '';
      });
    } catch (e) {
      component.state.alertDialog('Rejection Failed', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSaveAgentSettings() async {
    setState(() => _isLoading = true);
    try {
      final updatedAgent = component.state.activeP2pAgent.copyWith(
        name: _agentName.trim(),
        phone: _agentPhone.trim(),
        email: _agentEmail.trim(),
        isActive: _isActive,
        gcashAccountName: _gcashAccountName.trim(),
        gcashNumber: _gcashNumber.trim(),
        gcashQrUrl: _gcashQrUrl.trim(),
        mayaAccountName: _mayaAccountName.trim(),
        mayaNumber: _mayaNumber.trim(),
        mayaQrUrl: _mayaQrUrl.trim(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await component.state.handleSaveP2pAgentSettings(updatedAgent);
      component.state.showAppToast('Settings Saved', 'P2P payment QR codes and details updated successfully.');
    } catch (e) {
      component.state.alertDialog('Save Error', e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final requests = s.pendingDepositRequests;

    // Filter requests
    final filtered = requests.where((r) {
      if (_statusFilter != 'ALL' && r.status.toUpperCase() != _statusFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesRef = r.referenceNumber.toLowerCase().contains(q);
        final matchesUser = r.userName.toLowerCase().contains(q) || r.userEmail.toLowerCase().contains(q);
        final matchesMethod = r.paymentMethod.toLowerCase().contains(q);
        return matchesRef || matchesUser || matchesMethod;
      }
      return true;
    }).toList();

    final pendingCount = requests.where((r) => r.status.toUpperCase() == 'PENDING_VERIFICATION').length;
    final approvedCount = requests.where((r) => r.status.toUpperCase() == 'APPROVED').length;
    final totalPendingAmount = requests
        .where((r) => r.status.toUpperCase() == 'PENDING_VERIFICATION')
        .fold<double>(0.0, (sum, r) => sum + r.amount);

    return div(classes: 'space-y-6 animate-fadeIn pb-12', [
      // ── Header Banner ──────────────────────────────────────────────────────
      div(
        classes:
            'p-6 sm:p-7 rounded-3xl ${isDark ? "bg-zinc-900/90 border border-zinc-800" : "bg-white border border-zinc-200"} shadow-xl relative overflow-hidden',
        [
          div(classes: 'flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10', [
            div(classes: 'space-y-1', [
              div(classes: 'flex items-center gap-2.5', [
                span(
                  classes:
                      'px-2.5 py-1 rounded-full text-[10px] font-extrabold uppercase tracking-wider ${s.activeP2pAgent.isActive ? "bg-emerald-500/20 text-emerald-400 border border-emerald-500/30" : "bg-zinc-800 text-zinc-400"}',
                  [Component.text(s.activeP2pAgent.isActive ? 'Desk Online' : 'Desk Offline')],
                ),
                span(classes: 'text-xs text-zinc-400 font-medium', [
                  Component.text('Agent: ${s.activeP2pAgent.name}'),
                ]),
              ]),
              h2(classes: 'text-2xl sm:text-3xl font-black text-white tracking-tight', [
                Component.text('P2P Agent & Admin Desk'),
              ]),
              p(classes: 'text-xs sm:text-sm text-zinc-400', [
                Component.text('Review manual GCash & Maya receipts, verify references, and configure official QR codes.'),
              ]),
            ]),

            // Quick Stats Strip
            div(classes: 'flex items-center gap-3 shrink-0', [
              div(
                classes:
                    'px-4 py-2.5 rounded-2xl ${isDark ? "bg-zinc-800/60 border border-zinc-700/60" : "bg-zinc-100"} text-center',
                [
                  span(classes: 'text-[10px] uppercase font-bold text-zinc-400 block', [Component.text('Pending')]),
                  span(classes: 'text-lg font-black text-amber-400', [Component.text('$pendingCount reqs')]),
                ],
              ),
              div(
                classes:
                    'px-4 py-2.5 rounded-2xl ${isDark ? "bg-zinc-800/60 border border-zinc-700/60" : "bg-zinc-100"} text-center',
                [
                  span(classes: 'text-[10px] uppercase font-bold text-zinc-400 block', [Component.text('Pending Volume')]),
                  span(classes: 'text-lg font-black text-emerald-400', [
                    Component.text('₱${totalPendingAmount.toStringAsFixed(0)}'),
                  ]),
                ],
              ),
              button(
                classes:
                    'px-4 py-2.5 rounded-2xl bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-xs font-bold transition flex items-center gap-1.5 cursor-pointer border border-zinc-700',
                events: {'click': (_) => _loadRequests()},
                [
                  lIcon('refresh-cw', cls: 'w-4 h-4 ${_isLoading ? "animate-spin" : ""}'),
                  Component.text('Refresh'),
                ],
              ),
            ]),
          ]),
        ],
      ),

      // ── Main Tabs Navigation ───────────────────────────────────────────────
      div(classes: 'flex items-center gap-2 border-b border-zinc-800 pb-2', [
        button(
          classes:
              'px-5 py-2.5 rounded-xl text-xs font-bold transition cursor-pointer border-0 flex items-center gap-2 '
              '${_activeTab == "queue" ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/20" : "text-zinc-400 hover:text-zinc-200 bg-zinc-900/60 border border-zinc-800"}',
          events: {'click': (_) => setState(() => _activeTab = 'queue')},
          [
            lIcon('list-checks', cls: 'w-4 h-4'),
            Component.text('Verification Queue ($pendingCount pending)'),
          ],
        ),
        button(
          classes:
              'px-5 py-2.5 rounded-xl text-xs font-bold transition cursor-pointer border-0 flex items-center gap-2 '
              '${_activeTab == "settings" ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/20" : "text-zinc-400 hover:text-zinc-200 bg-zinc-900/60 border border-zinc-800"}',
          events: {
            'click': (_) {
              _initAgentForm();
              setState(() => _activeTab = 'settings');
            }
          },
          [
            lIcon('qr-code', cls: 'w-4 h-4'),
            Component.text('Agent QR & Payment Settings'),
          ],
        ),
      ]),

      // ── Tab 1: Deposit Verification Queue ──────────────────────────────────
      if (_activeTab == 'queue') ...[
        // Filter & Search Controls
        div(classes: 'flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3', [
          // Filter pills
          div(classes: 'flex items-center gap-1.5 overflow-x-auto pb-1', [
            for (var opt in [
              ('ALL', 'All Requests (${requests.length})'),
              ('PENDING_VERIFICATION', 'Pending ($pendingCount)'),
              ('APPROVED', 'Approved ($approvedCount)'),
              ('REJECTED', 'Rejected'),
            ])
              button(
                classes:
                    'px-3.5 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition cursor-pointer border-0 '
                    '${_statusFilter == opt.$1 ? "bg-zinc-200 text-zinc-900 font-bold" : "bg-zinc-900 text-zinc-400 hover:text-zinc-200 border border-zinc-800"}',
                events: {'click': (_) => setState(() => _statusFilter = opt.$1)},
                [Component.text(opt.$2)],
              ),
          ]),

          // Search Box
          div(classes: 'relative w-full md:w-72', [
            div(classes: 'absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-zinc-500', [
              lIcon('search', cls: 'w-4 h-4'),
            ]),
            input(
              type: InputType.text,
              classes:
                  'w-full pl-9 pr-4 py-2 bg-zinc-900 border border-zinc-800 rounded-xl text-xs text-white placeholder:text-zinc-600 focus:outline-none focus:border-indigo-500 transition',
              attributes: {'placeholder': 'Search reference or name...'},
              events: {'input': (e) => setState(() => _searchQuery = getInputValue(e.target))},
            ),
          ]),
        ]),

        // Requests List
        if (filtered.isEmpty)
          div(
            classes:
                'p-12 text-center rounded-3xl bg-zinc-900/40 border border-zinc-800/80 text-zinc-500 space-y-2',
            [
              lIcon('check-circle', cls: 'w-8 h-8 mx-auto text-zinc-600'),
              h4(classes: 'text-base font-bold text-zinc-400', [Component.text('No deposit requests in this view')]),
              p(classes: 'text-xs text-zinc-600', [Component.text('New incoming P2P deposits will automatically queue here.')]),
            ],
          )
        else
          div(classes: 'space-y-3', [
            for (final req in filtered) _buildDepositRequestCard(req, isDark),
          ]),
      ],

      // ── Tab 2: Agent QR & Payment Settings ─────────────────────────────────
      if (_activeTab == 'settings') ...[
        div(
          classes:
              'p-6 sm:p-8 rounded-3xl bg-zinc-900 border border-zinc-800 space-y-6 text-white max-w-3xl',
          [
            div(classes: 'border-b border-zinc-800 pb-4 flex items-center justify-between', [
              div([
                h3(classes: 'text-lg font-bold', [Component.text('P2P Desk Credentials & Payment QR Codes')]),
                p(classes: 'text-xs text-zinc-400', [
                  Component.text('These numbers, account names, and QR codes are displayed to Nyxians when topping up their wallet.'),
                ]),
              ]),
              div(classes: 'flex items-center gap-2', [
                span(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Receiving Status:')]),
                button(
                  classes:
                      'px-3 py-1 rounded-full text-xs font-bold cursor-pointer transition border-0 '
                      '${_isActive ? "bg-emerald-500 text-white" : "bg-zinc-800 text-zinc-400"}',
                  events: {'click': (_) => setState(() => _isActive = !_isActive)},
                  [Component.text(_isActive ? 'Active / Online' : 'Inactive / Paused')],
                ),
              ]),
            ]),

            div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-4', [
              div(classes: 'space-y-1.5', [
                label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Agent Display Name')]),
                input(
                  type: InputType.text,
                  classes:
                      'w-full px-3.5 py-2.5 bg-zinc-800/80 border border-zinc-700/80 rounded-xl text-xs text-white focus:outline-none focus:border-indigo-500',
                  attributes: {'value': _agentName},
                  events: {'input': (e) => _agentName = getInputValue(e.target)},
                ),
              ]),
              div(classes: 'space-y-1.5', [
                label(classes: 'text-xs font-bold text-zinc-400', [Component.text('Contact Phone / Mobile')]),
                input(
                  type: InputType.text,
                  classes:
                      'w-full px-3.5 py-2.5 bg-zinc-800/80 border border-zinc-700/80 rounded-xl text-xs text-white focus:outline-none focus:border-indigo-500',
                  attributes: {'value': _agentPhone},
                  events: {'input': (e) => _agentPhone = getInputValue(e.target)},
                ),
              ]),
            ]),

            // GCash Config Section
            div(classes: 'p-5 rounded-2xl bg-zinc-800/40 border border-blue-500/20 space-y-4', [
              div(classes: 'flex items-center gap-2', [
                div(classes: 'w-3 h-3 rounded-full bg-[#007DFE]', []),
                h4(classes: 'text-sm font-bold text-blue-400', [Component.text('GCash Direct Config')]),
              ]),
              div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-4', [
                div(classes: 'space-y-1.5', [
                  label(classes: 'text-xs font-semibold text-zinc-400', [Component.text('GCash Account Name')]),
                  input(
                    type: InputType.text,
                    classes:
                        'w-full px-3.5 py-2 bg-zinc-900 border border-zinc-700 rounded-xl text-xs text-white focus:outline-none focus:border-blue-500',
                    attributes: {'value': _gcashAccountName},
                    events: {'input': (e) => _gcashAccountName = getInputValue(e.target)},
                  ),
                ]),
                div(classes: 'space-y-1.5', [
                  label(classes: 'text-xs font-semibold text-zinc-400', [Component.text('GCash Mobile Number')]),
                  input(
                    type: InputType.text,
                    classes:
                        'w-full px-3.5 py-2 bg-zinc-900 border border-zinc-700 rounded-xl text-xs text-white focus:outline-none focus:border-blue-500',
                    attributes: {'value': _gcashNumber},
                    events: {'input': (e) => _gcashNumber = getInputValue(e.target)},
                  ),
                ]),
              ]),
              div(classes: 'space-y-1.5', [
                label(classes: 'text-xs font-semibold text-zinc-400', [Component.text('GCash QR Code Image URL / Link')]),
                div(classes: 'flex gap-2', [
                  input(
                    type: InputType.text,
                    classes:
                        'flex-1 px-3.5 py-2 bg-zinc-900 border border-zinc-700 rounded-xl text-xs text-white focus:outline-none focus:border-blue-500',
                    attributes: {'value': _gcashQrUrl},
                    events: {'input': (e) => setState(() => _gcashQrUrl = getInputValue(e.target))},
                  ),
                  if (_gcashQrUrl.isNotEmpty)
                    button(
                      classes:
                          'px-3 py-2 bg-zinc-800 hover:bg-zinc-700 text-xs font-semibold text-zinc-300 rounded-xl cursor-pointer border border-zinc-700',
                      events: {'click': (_) => setState(() => _previewImageUrl = _gcashQrUrl)},
                      [Component.text('Preview')],
                    ),
                ]),
              ]),
            ]),

            // Maya Config Section
            div(classes: 'p-5 rounded-2xl bg-zinc-800/40 border border-emerald-500/20 space-y-4', [
              div(classes: 'flex items-center gap-2', [
                div(classes: 'w-3 h-3 rounded-full bg-[#00D084]', []),
                h4(classes: 'text-sm font-bold text-emerald-400', [Component.text('Maya Direct Config')]),
              ]),
              div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-4', [
                div(classes: 'space-y-1.5', [
                  label(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Maya Account Name')]),
                  input(
                    type: InputType.text,
                    classes:
                        'w-full px-3.5 py-2 bg-zinc-900 border border-zinc-700 rounded-xl text-xs text-white focus:outline-none focus:border-emerald-500',
                    attributes: {'value': _mayaAccountName},
                    events: {'input': (e) => _mayaAccountName = getInputValue(e.target)},
                  ),
                ]),
                div(classes: 'space-y-1.5', [
                  label(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Maya Mobile Number')]),
                  input(
                    type: InputType.text,
                    classes:
                        'w-full px-3.5 py-2 bg-zinc-900 border border-zinc-700 rounded-xl text-xs text-white focus:outline-none focus:border-emerald-500',
                    attributes: {'value': _mayaNumber},
                    events: {'input': (e) => _mayaNumber = getInputValue(e.target)},
                  ),
                ]),
              ]),
              div(classes: 'space-y-1.5', [
                label(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Maya QR Code Image URL / Link')]),
                div(classes: 'flex gap-2', [
                  input(
                    type: InputType.text,
                    classes:
                        'flex-1 px-3.5 py-2 bg-zinc-900 border border-zinc-700 rounded-xl text-xs text-white focus:outline-none focus:border-emerald-500',
                    attributes: {'value': _mayaQrUrl},
                    events: {'input': (e) => setState(() => _mayaQrUrl = getInputValue(e.target))},
                  ),
                  if (_mayaQrUrl.isNotEmpty)
                    button(
                      classes:
                          'px-3 py-2 bg-zinc-800 hover:bg-zinc-700 text-xs font-semibold text-zinc-300 rounded-xl cursor-pointer border border-zinc-700',
                      events: {'click': (_) => setState(() => _previewImageUrl = _mayaQrUrl)},
                      [Component.text('Preview')],
                    ),
                ]),
              ]),
            ]),

            // Save Actions
            div(classes: 'flex justify-end pt-2', [
              button(
                classes:
                    'px-6 py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition shadow-lg shadow-indigo-600/30 cursor-pointer border-0 flex items-center gap-2 active:scale-95',
                events: {'click': (_) => _handleSaveAgentSettings()},
                [
                  if (_isLoading) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                  Component.text('Save P2P Agent Settings'),
                ],
              ),
            ]),
          ],
        ),
      ],

      // ── Full-Size Image Preview Modal ──────────────────────────────────────
      if (_previewImageUrl != null)
        div(
          classes:
              'fixed inset-0 z-[200] flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-fadeIn',
          events: {'click': (_) => setState(() => _previewImageUrl = null)},
          [
            div(
              classes:
                  'relative max-w-lg max-h-[85vh] bg-zinc-900 border border-zinc-800 rounded-3xl p-4 shadow-2xl overflow-hidden',
              events: {'click': (e) => e.stopPropagation()},
              [
                div(classes: 'flex items-center justify-between pb-3 border-b border-zinc-800 mb-3', [
                  span(classes: 'text-xs font-bold text-zinc-300', [Component.text('Receipt / QR Code Inspector')]),
                  button(
                    classes: 'w-7 h-7 rounded-full bg-zinc-800 hover:bg-zinc-700 text-zinc-400 flex items-center justify-center cursor-pointer border-0',
                    events: {'click': (_) => setState(() => _previewImageUrl = null)},
                    [span(classes: 'lucide lucide-x text-xs', [])],
                  ),
                ]),
                img(
                  src: _previewImageUrl!,
                  classes: 'w-full max-h-[70vh] object-contain rounded-2xl bg-black/50',
                  alt: 'Payment Proof',
                ),
              ],
            ),
          ],
        ),

      // ── Rejection Reason Modal ─────────────────────────────────────────────
      if (_rejectingDepositId != null)
        div(
          classes:
              'fixed inset-0 z-[200] flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-fadeIn',
          [
            div(
              classes:
                  'w-full max-w-md bg-zinc-900 border border-zinc-800 rounded-3xl p-6 shadow-2xl space-y-4 text-white',
              [
                div(classes: 'flex items-center justify-between border-b border-zinc-800 pb-3', [
                  div(classes: 'flex items-center gap-2 text-red-400 font-bold text-sm', [
                    lIcon('alert-triangle', cls: 'w-4 h-4'),
                    Component.text('Reject Deposit Request'),
                  ]),
                  button(
                    classes: 'w-7 h-7 rounded-full bg-zinc-800 hover:bg-zinc-700 text-zinc-400 flex items-center justify-center cursor-pointer border-0',
                    events: {'click': (_) => setState(() => _rejectingDepositId = null)},
                    [span(classes: 'lucide lucide-x text-xs', [])],
                  ),
                ]),
                p(classes: 'text-xs text-zinc-400 leading-relaxed', [
                  Component.text('Please specify the reason for rejecting this deposit. The reason will be recorded and sent to the user.'),
                ]),
                textarea(
                  classes:
                      'w-full p-3 bg-zinc-950 border border-zinc-800 rounded-2xl text-xs text-white focus:outline-none focus:border-red-500 min-h-[90px] resize-none',
                  attributes: {'placeholder': 'e.g. Reference number does not match receipt, amount incorrect...'},
                  events: {'input': (e) => _rejectionReason = getInputValue(e.target)},
                  [],
                ),
                div(classes: 'flex justify-end gap-2 pt-2', [
                  button(
                    classes: 'px-4 py-2 rounded-xl text-xs font-semibold text-zinc-400 hover:bg-zinc-800 cursor-pointer border-0',
                    events: {'click': (_) => setState(() => _rejectingDepositId = null)},
                    [Component.text('Cancel')],
                  ),
                  button(
                    classes:
                        'px-5 py-2 rounded-xl bg-red-600 hover:bg-red-500 text-white text-xs font-bold transition shadow cursor-pointer border-0 active:scale-95',
                    events: {'click': (_) => _handleRejectSubmit()},
                    [
                      if (_isLoading) lIcon('loader', cls: 'w-4 h-4 animate-spin'),
                      Component.text('Confirm Rejection'),
                    ],
                  ),
                ]),
              ],
            ),
          ],
        ),
    ]);
  }

  Component _buildDepositRequestCard(DepositRequest req, bool isDark) {
    final status = req.status.toUpperCase();
    final isWaitingAgent = status == 'WAITING_FOR_AGENT';
    final isAwaitingPayment = status == 'AWAITING_PAYMENT';
    final isPendingVerification = status == 'PENDING_VERIFICATION';
    final isApproved = status == 'APPROVED';
    final isCancelled = status == 'CANCELLED';
    final isGcash = req.paymentMethod.toLowerCase().contains('gcash');

    final agent = component.state.activeP2pAgent;
    final defaultAccountName = isGcash ? agent.gcashAccountName : agent.mayaAccountName;
    final defaultAccountNumber = isGcash ? agent.gcashNumber : agent.mayaNumber;
    final defaultQrUrl = isGcash ? agent.gcashQrUrl : agent.mayaQrUrl;

    return div(
      classes:
          'p-5 rounded-2xl ${isDark ? "bg-zinc-900/90 border border-zinc-800/90" : "bg-white border border-zinc-200"} shadow-sm hover:border-zinc-700 transition flex flex-col md:flex-row md:items-center justify-between gap-4',
      [
        // Left: User info + Payment rail badge
        div(classes: 'flex items-start gap-3.5', [
          // Receipt or QR Thumbnail
          if (req.proofImageUrl.isNotEmpty)
            div(
              classes:
                  'w-16 h-16 rounded-xl bg-zinc-800 border border-zinc-700 overflow-hidden shrink-0 cursor-pointer hover:opacity-80 transition relative group',
              events: {'click': (_) => setState(() => _previewImageUrl = req.proofImageUrl)},
              [
                img(
                  src: req.proofImageUrl,
                  classes: 'w-full h-full object-cover',
                  alt: 'Receipt Thumbnail',
                ),
                div(
                  classes:
                      'absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition text-white',
                  [
                    lIcon('zoom-in', cls: 'w-4 h-4'),
                  ],
                ),
              ],
            )
          else if (req.agentQrUrl != null && req.agentQrUrl!.isNotEmpty)
            div(
              classes:
                  'w-16 h-16 rounded-xl bg-white border border-zinc-700 overflow-hidden shrink-0 cursor-pointer hover:opacity-80 transition relative group p-1',
              events: {'click': (_) => setState(() => _previewImageUrl = req.agentQrUrl)},
              [
                img(
                  src: req.agentQrUrl!,
                  classes: 'w-full h-full object-contain',
                  alt: 'Agent QR',
                ),
              ],
            )
          else
            div(
              classes:
                  'w-16 h-16 rounded-xl bg-zinc-800 flex items-center justify-center text-zinc-500 shrink-0',
              [
                lIcon(isWaitingAgent ? 'radio' : 'file-text', cls: 'w-6 h-6 ${isWaitingAgent ? "text-indigo-400 animate-pulse" : ""}'),
              ],
            ),

          // User details
          div(classes: 'space-y-1', [
            div(classes: 'flex items-center gap-2 flex-wrap', [
              span(classes: 'text-sm font-bold text-white', [Component.text(req.userName)]),
              span(
                classes:
                    'px-2 py-0.5 rounded-md text-[10px] font-bold ${isGcash ? "bg-blue-500/20 text-blue-400 border border-blue-500/30" : "bg-emerald-500/20 text-emerald-400 border border-emerald-500/30"}',
                [Component.text(req.paymentMethod)],
              ),
              span(
                classes:
                    'px-2 py-0.5 rounded-md text-[10px] font-bold '
                    '${isWaitingAgent ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/30 animate-pulse" : isAwaitingPayment ? "bg-cyan-500/20 text-cyan-400 border border-cyan-500/30" : isPendingVerification ? "bg-amber-500/20 text-amber-400 border border-amber-500/30" : isApproved ? "bg-emerald-500/20 text-emerald-400 border border-emerald-500/30" : "bg-red-500/20 text-red-400 border border-red-500/30"}',
                [
                  Component.text(
                    isWaitingAgent
                        ? 'Needs Agent QR'
                        : isAwaitingPayment
                        ? 'QR Sent / Waiting Payment'
                        : isPendingVerification
                        ? 'Pending Verification'
                        : isApproved
                        ? 'Approved'
                        : isCancelled
                        ? 'Cancelled'
                        : 'Rejected',
                  ),
                ],
              ),
            ]),

            div(classes: 'text-xs text-zinc-400 flex items-center gap-2 flex-wrap', [
              span([Component.text(req.userEmail)]),
              if (req.referenceNumber.isNotEmpty) ...[
                span(classes: 'text-zinc-600', [Component.text('•')]),
                span([Component.text('Ref: ${req.referenceNumber}')]),
                button(
                  classes:
                      'p-0.5 text-zinc-400 hover:text-white bg-transparent border-0 cursor-pointer transition',
                  events: {
                    'click': (_) {
                      web.window.navigator.clipboard.writeText(req.referenceNumber);
                      component.state.showAppToast('Copied', 'Reference ${req.referenceNumber} copied');
                    }
                  },
                  [lIcon('copy', cls: 'w-3 h-3')],
                ),
              ],
              if (req.agentName != null) ...[
                span(classes: 'text-zinc-600', [Component.text('•')]),
                span(classes: 'text-zinc-400', [Component.text('Agent: ${req.agentName}')]),
              ],
            ]),

            if (req.rejectionReason != null && req.rejectionReason!.isNotEmpty)
              div(classes: 'text-[11px] text-red-400/90 pt-0.5 flex items-center gap-1', [
                lIcon('alert-circle', cls: 'w-3.5 h-3.5 shrink-0'),
                span([Component.text('Reason: ${req.rejectionReason}')]),
              ]),
          ]),
        ]),

        // Right: Amount + Action Buttons
        div(classes: 'flex items-center justify-between md:justify-end gap-4 shrink-0 pt-2 md:pt-0 border-t md:border-0 border-zinc-800/80', [
          div(classes: 'text-left md:text-right', [
            span(classes: 'text-[10px] uppercase font-bold text-zinc-500 block', [Component.text('Amount')]),
            span(classes: 'text-lg font-black text-white', [
              Component.text('₱${req.amount.toStringAsFixed(2)}'),
            ]),
          ]),

          if (isWaitingAgent)
            button(
              classes:
                  'px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition shadow-md shadow-indigo-600/30 cursor-pointer border-0 flex items-center gap-1.5 active:scale-95 animate-bounce',
              events: {
                'click': (_) async {
                  setState(() => _isLoading = true);
                  try {
                    await component.state.handleAgentSendQr(
                      depositRequestId: req.id,
                      agentAccountName: defaultAccountName,
                      agentAccountNumber: defaultAccountNumber,
                      agentQrUrl: defaultQrUrl,
                    );
                  } catch (e) {
                    component.state.alertDialog('Error Sending QR', e.toString());
                  } finally {
                    setState(() => _isLoading = false);
                  }
                }
              },
              [
                lIcon('send', cls: 'w-3.5 h-3.5'),
                Component.text('Send My ${req.paymentMethod} QR'),
              ],
            )
          else if (isAwaitingPayment)
            span(classes: 'text-xs text-cyan-400 font-semibold bg-cyan-500/10 px-3 py-1.5 rounded-xl border border-cyan-500/20', [
              Component.text('Waiting for Nyxian to pay...'),
            ])
          else if (isPendingVerification)
            div(classes: 'flex items-center gap-2', [
              button(
                classes:
                    'px-3.5 py-2 rounded-xl bg-red-500/10 hover:bg-red-500/20 text-red-400 text-xs font-bold transition cursor-pointer border border-red-500/30 flex items-center gap-1.5 active:scale-95',
                events: {'click': (_) => setState(() => _rejectingDepositId = req.id)},
                [
                  lIcon('x', cls: 'w-3.5 h-3.5'),
                  Component.text('Reject'),
                ],
              ),
              button(
                classes:
                    'px-4 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold transition shadow-md shadow-emerald-600/30 cursor-pointer border-0 flex items-center gap-1.5 active:scale-95',
                events: {'click': (_) => _handleApprove(req)},
                [
                  lIcon('check', cls: 'w-3.5 h-3.5'),
                  Component.text('Approve & Credit'),
                ],
              ),
            ])
          else
            span(classes: 'text-xs text-zinc-500 font-medium', [
              Component.text(isApproved ? 'Verified & Credited' : isCancelled ? 'Cancelled' : 'Closed'),
            ]),
        ]),
      ],
    );
  }
}
