import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class TransitViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const TransitViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final isRent = s.transitMode == TransitMode.rent;

    return div(classes: 'space-y-8 animate-fade-up', [
      // Header
      div(classes: 'flex items-center justify-between', [
        div([
          h1(classes: 'text-3xl font-extrabold tracking-tight', [Component.text('Transit Hub')]),
          p(classes: 'text-sm mt-1 ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            Component.text('Rent wheels or earn from your garage'),
          ]),
        ]),
        lIcon('car', cls: 'w-8 h-8 text-purple-400'),
      ]),

      // Mode toggle
      segmentedControl(
        options: const [('Rent a Vehicle', 'rent'), ('Host (My Garage)', 'host')],
        selected: isRent ? 'rent' : 'host',
        isDark: isDark,
        onChange: (v) => s.setState(() => s.transitMode = v == 'rent' ? TransitMode.rent : TransitMode.host),
      ),

      if (isRent) _rentView(isDark) else _hostView(isDark),
    ]);
  }

  Component _rentView(bool isDark) {
    final vehicles = [
      ('Toyota Fortuner', 'SUV', '₱ 2,500/day', '1.2 km'),
      ('Honda City', 'Sedan', '₱ 1,200/day', '0.8 km'),
      ('Ford Ranger', 'Pickup', '₱ 2,000/day', '2.4 km'),
      ('Mitsubishi Xpander', 'MPV', '₱ 1,800/day', '3.1 km'),
    ];

    return div(classes: 'space-y-6', [
      // Active rental card
      div(classes: 'p-5 rounded-2xl border border-purple-500/30 bg-purple-500/10', [
        div(classes: 'flex items-center gap-3 mb-3', [
          div(classes: 'p-2 rounded-xl bg-purple-500/20', [lIcon('car', cls: 'w-5 h-5 text-purple-400')]),
          div([
            p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
              Component.text('Active Rental'),
            ]),
            p(classes: 'font-bold', [Component.text('Toyota Fortuner • ABC-1234')]),
          ]),
        ]),
        div(classes: 'flex items-center justify-between', [
          p(classes: 'text-sm text-purple-300', [Component.text('Returns in 2 days')]),
          button(
            classes:
                'px-4 py-2 rounded-xl text-xs font-bold bg-purple-500/20 text-purple-300 hover:bg-purple-500/30 transition-colors',
            events: {},
            [Component.text('Extend')],
          ),
        ]),
      ]),

      // Search
      div(
        classes:
            'flex items-center gap-3 p-4 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
        [
          lIcon('search', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
          input(
            classes: 'bg-transparent border-none outline-none flex-1 text-sm',
            type: InputType.search,
            attributes: {'placeholder': 'Search vehicles, location...'},
          ),
        ],
      ),

      // Vehicle cards
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
        for (final v in vehicles) _vehicleCard(v.$1, v.$2, v.$3, v.$4, isDark),
      ]),
    ]);
  }

  Component _vehicleCard(String model, String type, String price, String distance, bool isDark) {
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-purple-500/40'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return div(classes: 'p-5 rounded-2xl border transition-all card-hover $cardCls', [
      div(classes: 'flex items-start justify-between mb-4', [
        div([
          p(classes: 'font-bold text-lg', [Component.text(model)]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"}', [Component.text(type)]),
        ]),
        span(classes: 'px-2 py-1 rounded-lg text-xs font-bold bg-purple-500/20 text-purple-400', [
          Component.text('AVAILABLE'),
        ]),
      ]),
      // Placeholder image area
      div(
        classes:
            'w-full h-28 rounded-xl mb-4 ${isDark ? "bg-zinc-800" : "bg-zinc-100"} flex items-center justify-center',
        [
          lIcon('car', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-300"}'),
        ],
      ),
      div(classes: 'flex items-center justify-between', [
        div([
          p(classes: 'font-bold text-lg text-purple-400', [Component.text(price)]),
          div(classes: 'flex items-center gap-1 text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            lIcon('map-pin', cls: 'w-3 h-3'),
            Component.text(' $distance'),
          ]),
        ]),
        button(
          classes:
              'px-4 py-2.5 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
          events: {},
          [Component.text('Book Now')],
        ),
      ]),
    ]);
  }

  Component _hostView(bool isDark) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    return div(classes: 'space-y-6', [
      div(classes: 'p-10 rounded-2xl border border-dashed text-center $cardCls', [
        div(classes: 'flex justify-center mb-5', [
          div(classes: 'p-5 rounded-2xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
            lIcon('car', cls: 'w-10 h-10 ${isDark ? "text-zinc-600" : "text-zinc-400"}'),
          ]),
        ]),
        h2(classes: 'text-xl font-bold mb-2', [Component.text('Turn your vehicle into earnings')]),
        p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"} max-w-xs mx-auto mb-6', [
          Component.text('List your car, motorcycle, or truck and earn while it\'s idle.'),
        ]),
        button(
          classes:
              'px-6 py-3 rounded-xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity inline-flex items-center gap-2',
          events: {},
          [lIcon('plus', cls: 'w-4 h-4'), Component.text(' List a Vehicle')],
        ),
      ]),
    ]);
  }
}
