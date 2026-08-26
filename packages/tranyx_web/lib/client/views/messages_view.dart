import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class MessagesViewComponent extends StatefulComponent {
  final TranyxAppState state;
  const MessagesViewComponent({required this.state, super.key});

  @override
  State<MessagesViewComponent> createState() => _MessagesViewComponentState();
}

class _MessagesViewComponentState extends State<MessagesViewComponent> {
  String selectedSection = 'active'; // 'active' or 'archived'
  String categoryFilter = 'all'; // 'all', 'job', 'rental', 'property', 'support'
  String searchQuery = '';

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final ms = raw is int ? raw : (raw as num).toInt();
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $h:$m $ampm';
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> _collectConversations() {
    final s = component.state;
    final uid = SessionStorage.uid ?? '';
    if (uid.isEmpty) return [];

    final list = <Map<String, dynamic>>[];

    // 1. Job Conversations
    for (final job in s.myJobs) {
      final id = job['id'] as String? ?? '';
      if (id.isEmpty) continue;
      final title = job['title'] as String? ?? 'Job Transaction';
      final status = (job['status'] as String? ?? 'Open').trim();
      final lowerStatus = status.toLowerCase();
      final isArchived = lowerStatus == 'completed' ||
          lowerStatus == 'complete' ||
          lowerStatus == 'done' ||
          lowerStatus == 'cancelled' ||
          lowerStatus == 'expired' ||
          lowerStatus == 'closed' ||
          lowerStatus == 'rejected';

      final creatorId = job['creatorId'] as String? ?? '';
      final isEmployer = creatorId == uid;
      final acceptedApplicant = job['acceptedApplicant'] as String? ?? job['acceptedApplicantName'] as String? ?? 'Contractor';
      final employerName = job['creatorName'] as String? ?? 'Client';
      final counterparty = isEmployer ? acceptedApplicant : employerName;
      final createdAt = job['createdAt'];

      list.add({
        'chatId': id,
        'type': 'job',
        'typeLabel': 'Job & Gig',
        'title': title,
        'counterparty': counterparty,
        'status': status,
        'isArchived': isArchived,
        'timestamp': createdAt is num ? createdAt.toInt() : 0,
        'dateStr': _formatDate(createdAt),
        'icon': 'briefcase',
      });
    }

    // Also include applied jobs for freelancers
    for (final job in s.appliedJobs) {
      final id = job['id'] as String? ?? '';
      if (id.isEmpty || list.any((c) => c['chatId'] == id)) continue;
      final title = job['title'] as String? ?? 'Applied Job';
      final status = (job['status'] as String? ?? 'Open').trim();
      final lowerStatus = status.toLowerCase();
      final isArchived = lowerStatus == 'completed' ||
          lowerStatus == 'complete' ||
          lowerStatus == 'done' ||
          lowerStatus == 'cancelled' ||
          lowerStatus == 'expired' ||
          lowerStatus == 'closed' ||
          lowerStatus == 'rejected';

      final employerName = job['creatorName'] as String? ?? 'Client';
      final createdAt = job['createdAt'];

      list.add({
        'chatId': id,
        'type': 'job',
        'typeLabel': 'Job & Gig',
        'title': title,
        'counterparty': employerName,
        'status': status,
        'isArchived': isArchived,
        'timestamp': createdAt is num ? createdAt.toInt() : 0,
        'dateStr': _formatDate(createdAt),
        'icon': 'briefcase',
      });
    }

    // 2. Vehicle Rental Conversations
    for (final rentalMap in s.realtimeRentals) {
      final id = rentalMap['id'] as String? ?? '';
      if (id.isEmpty) continue;
      final rental = VehicleRental.fromMap(rentalMap, id);
      final chatId = 'rental_$id';
      final title = '${rental.year} ${rental.brand} ${rental.model}';
      final status = rental.status;
      final lowerStatus = status.toLowerCase();
      final isArchived = lowerStatus == 'completed' ||
          lowerStatus == 'complete' ||
          lowerStatus == 'cancelled' ||
          lowerStatus == 'rejected' ||
          lowerStatus == 'expired' ||
          lowerStatus == 'closed';

      final isHost = rental.hostId == uid;
      final counterparty = isHost ? (rental.renteeName ?? 'Renter') : rental.hostName;
      final ts = rental.createdAt.millisecondsSinceEpoch;

      list.add({
        'chatId': chatId,
        'type': 'rental',
        'typeLabel': 'Vehicle Rental',
        'title': title,
        'counterparty': counterparty,
        'status': status,
        'isArchived': isArchived,
        'timestamp': ts,
        'dateStr': _formatDate(ts),
        'icon': 'car',
      });
    }

    // 3. Property Rental Conversations
    for (final prop in s.realtimeProperties) {
      final id = prop.id;
      if (id.isEmpty) continue;
      final chatId = 'property_$id';
      final title = prop.title;
      final status = prop.status.isNotEmpty ? prop.status : 'Available';
      final lowerStatus = status.toLowerCase();
      final isArchived = lowerStatus == 'completed' ||
          lowerStatus == 'cancelled' ||
          lowerStatus == 'expired' ||
          lowerStatus == 'closed';

      final isHost = prop.hostId == uid;
      final counterparty = isHost ? 'Renter' : prop.hostName;
      final ts = prop.createdAt.millisecondsSinceEpoch;

      list.add({
        'chatId': chatId,
        'type': 'property',
        'typeLabel': 'Property Rental',
        'title': title,
        'counterparty': counterparty,
        'status': status,
        'isArchived': isArchived,
        'timestamp': ts,
        'dateStr': _formatDate(ts),
        'icon': 'home',
      });
    }

    // 4. Customer Support Chat
    if (uid.isNotEmpty) {
      list.add({
        'chatId': 'support_$uid',
        'type': 'support',
        'typeLabel': 'Customer Support',
        'title': 'TRANYX Official Support Desk',
        'counterparty': 'Tranyx Support Agent',
        'status': 'Active',
        'isArchived': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'dateStr': '24/7 Dedicated Support',
        'icon': 'shield-check',
      });
    }

    // Sort descending by timestamp
    list.sort((itemA, itemB) => (itemB['timestamp'] as int).compareTo(itemA['timestamp'] as int));

    return list;
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    final allConversations = _collectConversations();
    final activeList = allConversations.where((c) => !c['isArchived']).toList();
    final archivedList = allConversations.where((c) => c['isArchived']).toList();

    final currentPool = selectedSection == 'active' ? activeList : archivedList;

    // Apply category filter and search query
    final filtered = currentPool.where((item) {
      if (categoryFilter != 'all') {
        if (item['type'] != categoryFilter) return false;
      }
      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final title = (item['title'] as String).toLowerCase();
        final counterparty = (item['counterparty'] as String).toLowerCase();
        final typeLabel = (item['typeLabel'] as String).toLowerCase();
        if (!title.contains(q) && !counterparty.contains(q) && !typeLabel.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return div(classes: 'max-w-6xl mx-auto space-y-6 animate-fade-in p-4 sm:p-6', [
      // ── Page Header ────────────────────────────────────────────────────────
      div(classes: 'flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b ${isDark ? "border-zinc-800" : "border-zinc-200"} pb-6', [
        div([
          div(classes: 'flex items-center gap-3', [
            div(classes: 'w-10 h-10 rounded-2xl bg-indigo-500/10 flex items-center justify-center text-indigo-400', [
              lIcon('message-circle', cls: 'w-6 h-6'),
            ]),
            div([
              h1(classes: 'text-2xl font-black ${isDark ? "text-white" : "text-zinc-900"}', [
                Component.text('Messages & Conversations'),
              ]),
              p(classes: 'text-xs text-zinc-500 mt-0.5', [
                Component.text('Communicate with clients, freelancers, hosts, and support safely inside Tranyx'),
              ]),
            ]),
          ]),
        ]),

        // Search Bar
        div(classes: 'relative w-full sm:w-72', [
          div(classes: 'absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-zinc-400', [
            lIcon('search', cls: 'w-4 h-4'),
          ]),
          input(
            type: InputType.text,
            classes:
                'w-full pl-10 pr-4 py-2 rounded-xl text-xs border ${isDark ? "bg-zinc-900/80 border-zinc-800 text-zinc-200" : "bg-white border-zinc-200 text-zinc-800"} outline-none focus:border-indigo-500 transition',
            attributes: {
              'placeholder': 'Search messages or counterparties...',
              'value': searchQuery,
            },
            events: {
              'input': (e) => setState(() => searchQuery = getInputValue(e.target)),
            },
          ),
        ]),
      ]),

      // ── Active vs Archived Section Switcher ─────────────────────────────────
      div(classes: 'flex items-center justify-between gap-4 flex-wrap', [
        div(classes: 'flex items-center gap-2 p-1 rounded-2xl ${isDark ? "bg-zinc-900/80 border border-zinc-800" : "bg-zinc-100 border border-zinc-200"}', [
          button(
            classes:
                'px-5 py-2.5 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-2 ${selectedSection == 'active' ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30" : "text-zinc-400 hover:text-zinc-200"}',
            events: {'click': (_) => setState(() => selectedSection = 'active')},
            [
              div([], classes: 'w-2 h-2 rounded-full ${selectedSection == 'active' ? "bg-white" : "bg-emerald-400"} animate-pulse'),
              Component.text('Active (${activeList.length})'),
            ],
          ),
          button(
            classes:
                'px-5 py-2.5 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-2 ${selectedSection == 'archived' ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30" : "text-zinc-400 hover:text-zinc-200"}',
            events: {'click': (_) => setState(() => selectedSection = 'archived')},
            [
              lIcon('archive', cls: 'w-3.5 h-3.5'),
              Component.text('Archived (${archivedList.length})'),
            ],
          ),
        ]),

        // Category Filter Pills
        div(classes: 'flex flex-wrap items-center gap-1.5', [
          for (final filter in [
            {'id': 'all', 'label': 'All Types'},
            {'id': 'job', 'label': 'Jobs & Gigs'},
            {'id': 'rental', 'label': 'Vehicle Rentals'},
            {'id': 'property', 'label': 'Properties'},
            {'id': 'support', 'label': 'Support'},
          ])
            button(
              classes:
                  'px-3 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer ${categoryFilter == filter['id'] ? "bg-zinc-800 text-indigo-400 border border-indigo-500/30" : "bg-zinc-800/40 text-zinc-400 hover:text-zinc-200 border border-zinc-800"}',
              events: {'click': (_) => setState(() => categoryFilter = filter['id']!)},
              [Component.text(filter['label']!)],
            ),
        ]),
      ]),

      // ── Information Banner for Archived Section ─────────────────────────────
      if (selectedSection == 'archived')
        div(
          classes:
              'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3 animate-fade-in',
          [
            lIcon('info', cls: 'w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5'),
            div([
              p(classes: 'text-xs font-bold text-amber-400', [
                Component.text('Archived Conversation History'),
              ]),
              p(classes: 'text-[11px] text-amber-300/90 mt-0.5 leading-relaxed', [
                Component.text(
                  'These conversations belong to completed, cancelled, or closed transactions. Complete message logs are preserved for your receipts, agreements, and records. Sending new messages is disabled.',
                ),
              ]),
            ]),
          ],
        ),

      // ── Conversations Feed ──────────────────────────────────────────────────
      if (filtered.isEmpty)
        div(
          classes:
              'p-16 text-center rounded-[2.5rem] border border-dashed ${isDark ? "border-zinc-800" : "border-zinc-300"} space-y-3',
          [
            div(
              classes:
                  'w-14 h-14 mx-auto rounded-2xl ${selectedSection == 'active' ? "bg-indigo-500/10 text-indigo-400" : "bg-zinc-800 text-zinc-500"} flex items-center justify-center',
              [
                lIcon(selectedSection == 'active' ? 'message-circle' : 'archive', cls: 'w-7 h-7'),
              ],
            ),
            h3(classes: 'text-base font-bold ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
              Component.text(
                selectedSection == 'active'
                    ? 'No Active Conversations'
                    : 'No Archived Conversations',
              ),
            ]),
            p(classes: 'text-xs text-zinc-500 max-w-sm mx-auto', [
              Component.text(
                selectedSection == 'active'
                    ? 'When you apply to a gig, hire an applicant, or book a rental, your active chat thread will appear here.'
                    : 'When transactions are completed or closed, their full conversation logs will be safely archived here for your reference.',
              ),
            ]),
          ],
        )
      else
        div(
          classes:
              'rounded-[2rem] border overflow-hidden $cardCls divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-200"}',
          [
            for (final conv in filtered)
              div(
                classes:
                    'p-5 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 hover:bg-zinc-500/5 transition-all cursor-pointer group',
                events: {
                  'click': (_) {
                    s.openChat(
                      conv['chatId'] as String,
                      title: conv['title'] as String?,
                      status: conv['status'] as String?,
                      isArchived: conv['isArchived'] as bool?,
                      closedDate: conv['dateStr'] as String?,
                      counterpartyName: conv['counterparty'] as String?,
                    );
                  },
                },
                [
                  div(classes: 'flex items-start gap-4 flex-1', [
                    // Icon / Avatar
                    div(
                      classes:
                          'relative w-12 h-12 rounded-2xl flex-shrink-0 flex items-center justify-center ${conv['isArchived'] ? "bg-zinc-800 text-zinc-400 border border-zinc-700" : (conv['type'] == 'support' ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/30" : "bg-indigo-500/10 text-indigo-400 border border-indigo-500/20")}',
                      [
                        lIcon(conv['icon'] as String? ?? 'message-circle', cls: 'w-6 h-6'),
                        if (!conv['isArchived'])
                          div([], classes: 'absolute -top-1 -right-1 w-3 h-3 rounded-full bg-emerald-500 border-2 ${isDark ? "border-zinc-900" : "border-white"} animate-pulse'),
                      ],
                    ),

                    div(classes: 'space-y-1 flex-1', [
                      div(classes: 'flex flex-wrap items-center gap-2', [
                        p(classes: 'font-bold text-sm ${isDark ? "text-zinc-100 group-hover:text-indigo-400" : "text-zinc-900 group-hover:text-indigo-600"} transition-colors', [
                          Component.text(conv['title'] as String),
                        ]),
                        span(
                          classes:
                              'text-[10px] font-extrabold px-2 py-0.5 rounded-full ${conv['isArchived'] ? "bg-zinc-800 text-zinc-400 border border-zinc-700" : "bg-indigo-500/10 text-indigo-400 border border-indigo-500/20"}',
                          [
                            Component.text(conv['typeLabel'] as String),
                          ],
                        ),
                      ]),

                      div(classes: 'flex flex-wrap items-center gap-2 text-xs text-zinc-400', [
                        span(classes: 'font-semibold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                          Component.text('With: ${conv['counterparty']}'),
                        ]),
                        span([Component.text('•')]),
                        span([Component.text(conv['dateStr'] as String)]),
                      ]),

                      p(classes: 'text-xs text-zinc-500 line-clamp-1 mt-1', [
                        Component.text(
                          conv['isArchived']
                              ? 'Transaction closed (${conv['status']}). Click to view complete chat history.'
                              : 'Active conversation. Click to send and receive real-time messages.',
                        ),
                      ]),
                    ]),
                  ]),

                  // Status and CTA Button
                  div(classes: 'flex items-center gap-3 w-full sm:w-auto justify-between sm:justify-end flex-shrink-0', [
                    // Status Badge
                    span(
                      classes:
                          'text-xs font-bold px-3 py-1 rounded-xl ${conv['status'].toString().toLowerCase() == 'completed' || conv['status'].toString().toLowerCase() == 'complete' ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30" : (conv['status'].toString().toLowerCase() == 'cancelled' || conv['status'].toString().toLowerCase() == 'rejected' ? "bg-rose-500/15 text-rose-400 border border-rose-500/30" : (conv['isArchived'] ? "bg-zinc-800 text-zinc-400 border border-zinc-700" : "bg-indigo-500/15 text-indigo-400 border border-indigo-500/30"))}',
                      [
                        Component.text(conv['status'] as String),
                      ],
                    ),

                    // Action Button
                    button(
                      classes:
                          'px-4 py-2 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${conv['isArchived'] ? (isDark ? "bg-zinc-800 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700") : "logo-gradient text-white shadow-md shadow-indigo-500/20 hover:opacity-90"}',
                      events: {},
                      [
                        lIcon(conv['isArchived'] ? 'file-text' : 'message-circle', cls: 'w-4 h-4'),
                        Component.text(conv['isArchived'] ? 'View History' : 'Open Chat'),
                      ],
                    ),
                  ]),
                ],
              ),
          ],
        ),
    ]);
  }
}
