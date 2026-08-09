import 'dart:async';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:web/web.dart' as web;
import '../services/map_interop.dart';
import '../services/web_interop.dart';
import 'map_container.dart';
import '../client/tranyx_app.dart';
import 'ui_helpers.dart';

/// A two-point Leaflet map picker.
/// Lets the employer click to set pickup point then destination point.
/// Records address + coords back into [TranyxAppState].
class MapPickerComponent extends StatefulComponent {
  final TranyxAppState state;
  const MapPickerComponent({required this.state, super.key});

  @override
  State<MapPickerComponent> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPickerComponent> {
  static const _mapId = 'job-map-picker';
  bool _geolocating = false;
  String _pickingFor = 'pickup'; // 'pickup' | 'destination'
  String _statusMsg = '';
  bool _ready = false;
  bool _confirming = false;
  String _searchQuery = '';
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _statusMsg = (component.state.selectedCategory?.hasTracker ?? false)
        ? 'Pan to 1st Point (e.g. Grocery Store)'
        : 'Pan to Site Location';
    _initMap();
  }

  Future<void> _initMap() async {
    print('DEBUG: _initMap started');
    await ensureMapLibreLoaded();
    print('DEBUG: MapLibre loaded');
    // initMap now polls for the DOM element itself — no fixed delay needed
    final isDark = component.state.isDark;
    await initMap(_mapId, 14.5995, 120.9842, 12, isDark: isDark);
    print('DEBUG: initMap called with isDark=$isDark');

    setState(() => _ready = true);
    print('DEBUG: _ready set to true');

    // Ensure map renders correctly after state update paints the div
    await Future.delayed(const Duration(milliseconds: 600));
    invalidateMapSize(_mapId);
    print('DEBUG: invalidateMapSize called');

    // Try to get user's real position for initial centre
    final pos = await getCurrentPosition();
    if (pos != null) {
      panTo(_mapId, pos.lat, pos.lng);
      print('DEBUG: panned to position: ${pos.lat}, ${pos.lng}');
      invalidateMapSize(_mapId);
    } else {
      print('DEBUG: Could not get current position');
    }
  }

  Future<void> _confirmCenterLocation() async {
    setState(() => _confirming = true);

    final center = getMapCenter(_mapId);
    if (center == null) {
      setState(() => _confirming = false);
      return;
    }

    final lat = center.lat;
    final lng = center.lng;

    final address = await reverseGeocode(lat, lng);
    final s = component.state;

    if (!(s.selectedCategory?.hasTracker ?? false)) {
      // Single point mode
      setMarker(_mapId, 'pickup', lat, lng, '📍 Site: $address');
      s.setState(() {
        s.pickupLat = lat;
        s.pickupLng = lng;
        s.pickupAddress = address;
        s.destinationLat = null;
        s.destinationLng = null;
        s.destinationAddress = '';
      });
      removeMarker(_mapId, 'destination');
      setState(() {
        _statusMsg = 'Site Location set! Pan to adjust.';
        _confirming = false;
      });
      return;
    }

    // Two point mode
    if (_pickingFor == 'pickup') {
      setMarker(_mapId, 'pickup', lat, lng, '📦 1st Point: $address');
      s.setState(() {
        s.pickupLat = lat;
        s.pickupLng = lng;
        s.pickupAddress = address;
      });
      setState(() {
        _pickingFor = 'destination';
        _statusMsg = 'Now pan to Delivery Point (e.g. House)';
        _confirming = false;
      });
    } else {
      setMarker(_mapId, 'destination', lat, lng, '🏠 Delivery Point: $address');
      s.setState(() {
        s.destinationLat = lat;
        s.destinationLng = lng;
        s.destinationAddress = address;
      });
      if (s.pickupLat != null && s.destinationLat != null) {
        drawOSRMRoute(
          _mapId,
          s.pickupLat!,
          s.pickupLng!,
          s.destinationLat!,
          s.destinationLng!,
          '#6366f1',
        );
      }
      setState(() {
        _pickingFor = 'pickup';
        _statusMsg = 'Route set! Pan to adjust 1st point.';
        _confirming = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _geolocating = true);
    component.state.isLocationEnabled = true;
    final pos = await getCurrentPosition();
    if (pos != null) {
      panTo(_mapId, pos.lat, pos.lng);
      component.state.userLatitude = pos.lat;
      component.state.userLongitude = pos.lng;
    }
    setState(() => _geolocating = false);
  }

  Future<void> _performSearch() async {
    final query = _searchQuery.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchResults = [];
    });
    try {
      final results = await searchAddress(query);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      print('ERROR: search failed: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _selectSearchResult(Map<String, dynamic> res) {
    final latStr = res['lat'] as String?;
    final lonStr = res['lon'] as String?;
    final displayName = res['display_name'] as String?;
    if (latStr != null && lonStr != null) {
      final lat = double.tryParse(latStr);
      final lng = double.tryParse(lonStr);
      if (lat != null && lng != null) {
        panTo(_mapId, lat, lng);
        setState(() {
          _searchResults = [];
          if (displayName != null) {
            _searchQuery = displayName;
          }
        });
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;

    return div(classes: 'space-y-4', [
      // Status bar
      div(
        classes:
            'flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium '
            '${_pickingFor == 'pickup' ? 'bg-blue-500/15 text-blue-400 border border-blue-500/30' : 'bg-green-500/15 text-green-400 border border-green-500/30'}',
        [
          lIcon(
            _pickingFor == 'pickup' ? 'map-pin' : 'flag',
            cls: 'w-4 h-4 flex-shrink-0',
          ),
          span([Component.text(_statusMsg)]),
        ],
      ),

      div(
        classes:
            'relative w-full rounded-2xl overflow-hidden border ${isDark ? "border-zinc-700" : "border-zinc-200"} shadow-inner',
        styles: Styles(raw: {'height': '320px'}),
        [
          // Map element
          MapContainer(
            key: const ValueKey('map-picker'),
            id: _mapId,
            classes: 'w-full h-full ${isDark ? "theme-dark" : "theme-light"}',
            styles: Styles(
              raw: {
                'z-index': '1',
                'position': 'absolute !important',
                'top': '0',
                'left': '0',
                'right': '0',
                'bottom': '0',
                'height': '100%',
                'width': '100%',
              },
            ),
          ),
          // Address search overlay
          if (_ready)
            div(
              classes: 'absolute top-3 left-3 right-3 z-[1010] flex flex-col gap-1.5',
              [
                div(
                  classes:
                      'flex gap-2 p-1.5 rounded-xl border shadow-lg backdrop-blur-md '
                      '${isDark ? "bg-zinc-900/95 border-zinc-700/80" : "bg-white/95 border-zinc-200/80"}',
                  [
                    lIcon('search', cls: 'w-4 h-4 my-auto ml-2 ${isDark ? "text-zinc-400" : "text-zinc-500"}'),
                    input(
                      classes:
                          'flex-1 bg-transparent border-0 outline-none text-sm px-1 '
                          '${isDark ? "text-white placeholder-zinc-500" : "text-zinc-900 placeholder-zinc-400"}',
                      attributes: {
                        'type': 'text',
                        'placeholder': 'Search address...',
                        'value': _searchQuery,
                      },
                      events: {
                        'input': (e) {
                          final val = getInputValue(e.target);
                          setState(() {
                            _searchQuery = val;
                            if (val.isEmpty) {
                              _searchResults = [];
                            }
                          });
                        },
                        'keydown': (e) {
                          final ke = e as web.KeyboardEvent;
                          if (ke.key == 'Enter') {
                            ke.preventDefault();
                            _performSearch();
                          }
                        },
                      },
                    ),
                    if (_searchQuery.isNotEmpty)
                      button(
                        classes: 'p-1 rounded-md hover:bg-zinc-500/20 my-auto',
                        events: {
                          'click': (_) {
                            setState(() {
                              _searchQuery = '';
                              _searchResults = [];
                            });
                          },
                        },
                        [
                          lIcon('x', cls: 'w-3.5 h-3.5 ${isDark ? "text-zinc-400" : "text-zinc-500"}'),
                        ],
                      ),
                    button(
                      classes:
                          'px-3 py-1.5 rounded-lg text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-500 transition-colors flex items-center gap-1',
                      events: {
                        'click': (_) => _performSearch(),
                      },
                      [
                        if (_isSearching) lIcon('loader-2', cls: 'w-3 h-3 animate-spin') else Component.text('Search'),
                      ],
                    ),
                  ],
                ),

                // Search Results dropdown
                if (_searchResults.isNotEmpty)
                  div(
                    classes:
                        'max-h-36 overflow-y-auto rounded-xl border shadow-xl flex flex-col divide-y '
                        '${isDark ? "bg-zinc-900 border-zinc-700 divide-zinc-800" : "bg-white border-zinc-200 divide-zinc-100"}',
                    _searchResults.map((res) {
                      final displayName = res['display_name'] as String? ?? '';
                      return button(
                        classes:
                            'px-4 py-2.5 text-left text-xs transition-colors hover:bg-indigo-600/10 '
                            '${isDark ? "text-zinc-300 hover:text-white" : "text-zinc-700 hover:text-indigo-900"}',
                        events: {
                          'click': (_) => _selectSearchResult(res),
                        },
                        [
                          span([Component.text(displayName)]),
                        ],
                      );
                    }).toList(),
                  ),
              ],
            ),
          // Loading overlay (shown until map is ready)
          div(
            classes:
                'absolute inset-0 flex flex-col items-center justify-center z-[400] '
                '${isDark ? "bg-zinc-900" : "bg-zinc-50"} '
                '${_ready ? "hidden" : ""}',
            [
              lIcon('loader-2', cls: 'w-8 h-8 animate-spin text-indigo-500'),
              p(classes: 'text-sm font-semibold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                Component.text('Loading map…'),
              ]),
            ],
          ),
          // Center pin overlay
          div(
            classes:
                'absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-full pointer-events-none z-[1000]',
            [
              lIcon(
                _pickingFor == 'pickup' ? 'map-pin' : 'flag',
                cls: 'w-8 h-8 drop-shadow-md ${_pickingFor == 'pickup' ? 'text-blue-500' : 'text-green-500'}',
              ),
              // Shadow dot at the tip of the pin
              div(
                classes:
                    'absolute bottom-0 left-1/2 transform -translate-x-1/2 translate-y-1 w-2 h-1 bg-black/30 rounded-full blur-[1px]',
                [],
              ),
            ],
          ),
        ],
      ),

      // Confirm Button
      if (_ready)
        button(
          classes:
              'w-full py-3.5 rounded-xl font-bold flex items-center justify-center gap-2 transition-all active:scale-[0.98] '
              '${_confirming ? 'bg-zinc-800 text-zinc-400 cursor-not-allowed' : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-lg shadow-indigo-500/20'}',
          events: _confirming ? {} : {'click': (_) => _confirmCenterLocation()},
          [
            if (_confirming) ...[
              lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
              Component.text('Confirming...'),
            ] else ...[
              lIcon('check-circle', cls: 'w-5 h-5'),
              Component.text(
                _pickingFor == 'pickup'
                    ? ((s.selectedCategory?.hasTracker ?? false) ? 'Confirm 1st Point' : 'Confirm Site Location')
                    : 'Confirm Delivery Point',
              ),
            ],
          ],
        ),

      // Use My Location button
      button(
        classes:
            'w-full py-3 rounded-xl border text-sm font-medium flex items-center justify-center gap-2 '
            '${isDark ? "border-zinc-700 text-zinc-400 hover:bg-zinc-800" : "border-zinc-200 text-zinc-600 hover:bg-zinc-50"} transition-colors',
        events: _geolocating ? {} : {'click': (_) => _useMyLocation()},
        [
          if (_geolocating) lIcon('loader-2', cls: 'w-4 h-4 animate-spin') else lIcon('navigation', cls: 'w-4 h-4'),
          Component.text('Pan to My Current Location'),
        ],
      ),

      // Location summaries
      if (s.pickupAddress.isNotEmpty || s.destinationAddress.isNotEmpty)
        div(classes: 'grid grid-cols-1 gap-2 pt-2', [
          if (s.pickupAddress.isNotEmpty)
            _locationCard(
              icon: 'package',
              label: (s.selectedCategory?.hasTracker ?? false) ? '1st Point' : 'Site Location',
              address: s.pickupAddress,
              color: 'blue',
              isDark: isDark,
              onClear: () {
                removeMarker(_mapId, 'pickup');
                if (s.selectedCategory?.hasTracker ?? false) removeMarker(_mapId, 'destination');
                s.setState(() {
                  s.pickupLat = null;
                  s.pickupLng = null;
                  s.pickupAddress = '';
                  s.destinationLat = null;
                  s.destinationLng = null;
                  s.destinationAddress = '';
                });
                setState(() {
                  _pickingFor = 'pickup';
                  _statusMsg = (s.selectedCategory?.hasTracker ?? false)
                      ? 'Pan to 1st Point (e.g. Grocery Store)'
                      : 'Pan to Site Location';
                });
              },
            ),
          if (s.destinationAddress.isNotEmpty)
            _locationCard(
              icon: 'home',
              label: 'Delivery Point',
              address: s.destinationAddress,
              color: 'green',
              isDark: isDark,
              onClear: () {
                removeMarker(_mapId, 'destination');
                s.setState(() {
                  s.destinationLat = null;
                  s.destinationLng = null;
                  s.destinationAddress = '';
                });
                setState(() => _statusMsg = 'Pan to Delivery Point (e.g. House)');
              },
            ),
        ]),
    ]);
  }

  Component _locationCard({
    required String icon,
    required String label,
    required String address,
    required String color,
    required bool isDark,
    required VoidCallback onClear,
  }) {
    final border = color == 'blue' ? 'border-blue-500/30' : 'border-green-500/30';
    final bg = color == 'blue' ? 'bg-blue-500/10' : 'bg-green-500/10';
    final textColor = color == 'blue' ? 'text-blue-400' : 'text-green-400';
    return div(
      classes: 'flex items-start gap-3 p-3 rounded-xl border $border $bg',
      [
        lIcon(icon, cls: 'w-4 h-4 $textColor flex-shrink-0 mt-0.5'),
        div(classes: 'flex-1 min-w-0', [
          p(classes: 'text-xs font-bold $textColor uppercase tracking-wide mb-0.5', [Component.text(label)]),
          p(
            classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-600"} truncate',
            [Component.text(address)],
          ),
        ]),
        button(
          classes: 'p-1 rounded-full hover:bg-zinc-500/20 flex-shrink-0',
          events: {'click': (_) => onClear()},
          [lIcon('x', cls: 'w-3 h-3 ${isDark ? "text-zinc-500" : "text-zinc-400"}')],
        ),
      ],
    );
  }
}

typedef VoidCallback = void Function();
