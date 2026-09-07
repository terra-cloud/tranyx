// Shared Jaspr UI helpers.
// Rules:
// - Use Component.text('...') — NOT text('...')
// - build() returns Component (single root)
// - CSS class strings are plain Tailwind tokens — no Dart calls inside them
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Renders a Lucide icon as an inline SVG so Jaspr fully owns the DOM node.
/// No Lucide JS runtime needed — zero conflicts with Jaspr's virtual DOM.
/// Each icon is stored as a list of SVG element descriptors rendered via proper
/// Jaspr DOM nodes (path, circle, line, polyline, polygon, rect).
Component lIcon(String name, {String cls = 'w-5 h-5'}) {
  final shapes = _lucideShapes[name] ?? _lucideShapes['help-circle']!;
  return svg(
    classes: '$cls pointer-events-none flex-shrink-0',
    attributes: {
      'xmlns': 'http://www.w3.org/2000/svg',
      'viewBox': '0 0 24 24',
      'fill': 'none',
      'stroke': 'currentColor',
      'stroke-width': '2',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
      'aria-hidden': 'true',
    },
    shapes.map(_renderShape).toList(),
  );
}

Component _renderShape(Map<String, String> s) {
  final tag = s['_tag']!;
  final attrs = Map<String, String>.from(s)..remove('_tag');
  return switch (tag) {
    'path'     => path(attributes: attrs, []),
    'circle'   => circle(attributes: attrs, []),
    'line'     => line(attributes: attrs, []),
    'polyline' => polyline(attributes: attrs, []),
    'polygon'  => polygon(attributes: attrs, []),
    'rect'     => rect(attributes: attrs, []),
    _          => path(attributes: attrs, []),
  };
}

/// Descriptor map — each icon is a list of SVG element maps.
/// '_tag' controls which Jaspr DOM element is rendered; remaining keys are attrs.
/// Descriptor map — each icon is a list of SVG element maps.
/// '_tag' controls which Jaspr DOM element is rendered; remaining keys are attrs.
const Map<String, List<Map<String, String>>> _lucideShapes = {
  'activity': [{'_tag':'polyline','points':'22 12 18 12 15 21 9 3 6 12 2 12'}],
  'alert-circle': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'line','x1':'12','y1':'8','x2':'12','y2':'12'},{'_tag':'line','x1':'12','y1':'16','x2':'12.01','y2':'16'}],
  'alert-triangle': [{'_tag':'path','d':'M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z'},{'_tag':'line','x1':'12','y1':'9','x2':'12','y2':'13'},{'_tag':'line','x1':'12','y1':'17','x2':'12.01','y2':'17'}],
  'arrow-down-left': [{'_tag':'line','x1':'17','y1':'7','x2':'7','y2':'17'},{'_tag':'polyline','points':'17 17 7 17 7 7'}],
  'arrow-left': [{'_tag':'line','x1':'19','y1':'12','x2':'5','y2':'12'},{'_tag':'polyline','points':'12 19 5 12 12 5'}],
  'arrow-right': [{'_tag':'line','x1':'5','y1':'12','x2':'19','y2':'12'},{'_tag':'polyline','points':'12 5 19 12 12 19'}],
  'arrow-up-right': [{'_tag':'line','x1':'7','y1':'17','x2':'17','y2':'7'},{'_tag':'polyline','points':'7 7 17 7 17 17'}],
  'award': [{'_tag':'circle','cx':'12','cy':'8','r':'6'},{'_tag':'path','d':'M15.477 12.89 17 22l-5-3-5 3 1.523-9.11'}],
  'bell': [{'_tag':'path','d':'M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9'},{'_tag':'path','d':'M13.73 21a2 2 0 0 1-3.46 0'}],
  'bell-off': [{'_tag':'path','d':'M8.56 2.9A7 7 0 0 1 19 9v4m-2 4H2s3-2 3-9a4.67 4.67 0 0 1 .08-.86'},{'_tag':'path','d':'M13.73 21a2 2 0 0 1-3.46 0'},{'_tag':'line','x1':'2','y1':'2','x2':'22','y2':'22'}],
  'briefcase': [{'_tag':'rect','x':'2','y':'7','width':'20','height':'14','rx':'2','ry':'2'},{'_tag':'path','d':'M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16'}],
  'calendar-check': [{'_tag':'rect','x':'3','y':'4','width':'18','height':'18','rx':'2','ry':'2'},{'_tag':'line','x1':'16','y1':'2','x2':'16','y2':'6'},{'_tag':'line','x1':'8','y1':'2','x2':'8','y2':'6'},{'_tag':'line','x1':'3','y1':'10','x2':'21','y2':'10'},{'_tag':'path','d':'m9 16 2 2 4-4'}],
  'camera': [{'_tag':'path','d':'M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'},{'_tag':'circle','cx':'12','cy':'13','r':'4'}],
  'car': [{'_tag':'path','d':'M5 17H3a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v9a2 2 0 0 1-2 2h-2'},{'_tag':'circle','cx':'7.5','cy':'17.5','r':'2.5'},{'_tag':'circle','cx':'17.5','cy':'17.5','r':'2.5'}],
  'check': [{'_tag':'polyline','points':'20 6 9 17 4 12'}],
  'check-circle': [{'_tag':'path','d':'M22 11.08V12a10 10 0 1 1-5.93-9.14'},{'_tag':'polyline','points':'22 4 12 14.01 9 11.01'}],
  'check-circle-2': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'path','d':'m9 12 2 2 4-4'}],
  'chevron-down': [{'_tag':'polyline','points':'6 9 12 15 18 9'}],
  'chevron-left': [{'_tag':'polyline','points':'15 18 9 12 15 6'}],
  'chevron-right': [{'_tag':'polyline','points':'9 18 15 12 9 6'}],
  'circle': [{'_tag':'circle','cx':'12','cy':'12','r':'10'}],
  'clock': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'polyline','points':'12 6 12 12 16 14'}],
  'compass': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'polygon','points':'16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76'}],
  'copy': [{'_tag':'rect','x':'9','y':'9','width':'13','height':'13','rx':'2','ry':'2'},{'_tag':'path','d':'M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1'}],
  'corner-down-right': [{'_tag':'polyline','points':'15 10 20 15 15 20'},{'_tag':'path','d':'M4 4v7a4 4 0 0 0 4 4h12'}],
  'credit-card': [{'_tag':'rect','x':'1','y':'4','width':'22','height':'16','rx':'2','ry':'2'},{'_tag':'line','x1':'1','y1':'10','x2':'23','y2':'10'}],
  'crosshair': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'line','x1':'22','y1':'12','x2':'18','y2':'12'},{'_tag':'line','x1':'6','y1':'12','x2':'2','y2':'12'},{'_tag':'line','x1':'12','y1':'6','x2':'12','y2':'2'},{'_tag':'line','x1':'12','y1':'22','x2':'12','y2':'18'}],
  'dollar-sign': [{'_tag':'line','x1':'12','y1':'1','x2':'12','y2':'23'},{'_tag':'path','d':'M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6'}],
  'edit-2': [{'_tag':'path','d':'M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z'}],
  'external-link': [{'_tag':'path','d':'M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6'},{'_tag':'polyline','points':'15 3 21 3 21 9'},{'_tag':'line','x1':'10','y1':'14','x2':'21','y2':'3'}],
  'eye': [{'_tag':'path','d':'M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z'},{'_tag':'circle','cx':'12','cy':'12','r':'3'}],
  'file-check': [{'_tag':'path','d':'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'},{'_tag':'polyline','points':'14 2 14 8 20 8'},{'_tag':'path','d':'m9 15 2 2 4-4'}],
  'file-text': [{'_tag':'path','d':'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'},{'_tag':'polyline','points':'14 2 14 8 20 8'},{'_tag':'line','x1':'16','y1':'13','x2':'8','y2':'13'},{'_tag':'line','x1':'16','y1':'17','x2':'8','y2':'17'},{'_tag':'polyline','points':'10 9 9 9 8 9'}],
  'flag': [{'_tag':'path','d':'M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z'},{'_tag':'line','x1':'4','y1':'22','x2':'4','y2':'15'}],
  'heart': [{'_tag':'path','d':'M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z'}],
  'help-circle': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'path','d':'M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3'},{'_tag':'line','x1':'12','y1':'17','x2':'12.01','y2':'17'}],
  'home': [{'_tag':'path','d':'m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'},{'_tag':'polyline','points':'9 22 9 12 15 12 15 22'}],
  'hourglass': [{'_tag':'path','d':'M5 22h14'},{'_tag':'path','d':'M5 2h14'},{'_tag':'path','d':'M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22'},{'_tag':'path','d':'M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2'}],
  'image': [{'_tag':'rect','x':'3','y':'3','width':'18','height':'18','rx':'2','ry':'2'},{'_tag':'circle','cx':'8.5','cy':'8.5','r':'1.5'},{'_tag':'polyline','points':'21 15 16 10 5 21'}],
  'info': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'line','x1':'12','y1':'8','x2':'12','y2':'12'},{'_tag':'line','x1':'12','y1':'16','x2':'12.01','y2':'16'}],
  'key': [{'_tag':'path','d':'m21 2-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4'}],
  'link': [{'_tag':'path','d':'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71'},{'_tag':'path','d':'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'}],
  'loader': [{'_tag':'line','x1':'12','y1':'2','x2':'12','y2':'6'},{'_tag':'line','x1':'12','y1':'18','x2':'12','y2':'22'},{'_tag':'line','x1':'4.93','y1':'4.93','x2':'7.76','y2':'7.76'},{'_tag':'line','x1':'16.24','y1':'16.24','x2':'19.07','y2':'19.07'},{'_tag':'line','x1':'2','y1':'12','x2':'6','y2':'12'},{'_tag':'line','x1':'18','y1':'12','x2':'22','y2':'12'},{'_tag':'line','x1':'4.93','y1':'19.07','x2':'7.76','y2':'16.24'},{'_tag':'line','x1':'16.24','y1':'7.76','x2':'19.07','y2':'4.93'}],
  'loader-2': [{'_tag':'path','d':'M21 12a9 9 0 1 1-6.219-8.56'}],
  'lock': [{'_tag':'rect','x':'3','y':'11','width':'18','height':'11','rx':'2','ry':'2'},{'_tag':'path','d':'M7 11V7a5 5 0 0 1 10 0v4'}],
  'log-out': [{'_tag':'path','d':'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4'},{'_tag':'polyline','points':'16 17 21 12 16 7'},{'_tag':'line','x1':'21','y1':'12','x2':'9','y2':'12'}],
  'mail': [{'_tag':'path','d':'M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z'},{'_tag':'polyline','points':'22,6 12,13 2,6'}],
  'map': [{'_tag':'polygon','points':'1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6'},{'_tag':'line','x1':'8','y1':'2','x2':'8','y2':'18'},{'_tag':'line','x1':'16','y1':'6','x2':'16','y2':'22'}],
  'map-pin': [{'_tag':'path','d':'M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z'},{'_tag':'circle','cx':'12','cy':'10','r':'3'}],
  'message-circle': [{'_tag':'path','d':'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'}],
  'message-circle-question': [{'_tag':'path','d':'M7.9 20A9 9 0 1 0 4 16.1L2 22Z'},{'_tag':'path','d':'M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3'},{'_tag':'line','x1':'12','y1':'17','x2':'12.01','y2':'17'}],
  'message-square': [{'_tag':'path','d':'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'}],
  'minus': [{'_tag':'line','x1':'5','y1':'12','x2':'19','y2':'12'}],
  'moon': [{'_tag':'path','d':'M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z'}],
  'navigation': [{'_tag':'polygon','points':'3 11 22 2 13 21 11 13 3 11'}],
  'pen-tool': [{'_tag':'path','d':'m12 19 7-7 3 3-7 7-3-3z'},{'_tag':'path','d':'m18 13-1.5-7.5L2 2l3.5 14.5L13 18l5-5z'},{'_tag':'path','d':'m2 2 7.586 7.586'},{'_tag':'circle','cx':'11','cy':'11','r':'2'}],
  'percent': [{'_tag':'line','x1':'19','y1':'5','x2':'5','y2':'19'},{'_tag':'circle','cx':'6.5','cy':'6.5','r':'2.5'},{'_tag':'circle','cx':'17.5','cy':'17.5','r':'2.5'}],
  'phone': [{'_tag':'path','d':'M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.15 13a19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 3.06 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L7.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 21 16.92z'}],
  'pin': [{'_tag':'line','x1':'12','y1':'17','x2':'12','y2':'22'},{'_tag':'path','d':'M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24z'}],
  'plus': [{'_tag':'line','x1':'12','y1':'5','x2':'12','y2':'19'},{'_tag':'line','x1':'5','y1':'12','x2':'19','y2':'12'}],
  'plus-circle': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'line','x1':'12','y1':'8','x2':'12','y2':'16'},{'_tag':'line','x1':'8','y1':'12','x2':'16','y2':'12'}],
  'qr-code': [{'_tag':'rect','x':'3','y':'3','width':'5','height':'5'},{'_tag':'rect','x':'16','y':'3','width':'5','height':'5'},{'_tag':'rect','x':'3','y':'16','width':'5','height':'5'},{'_tag':'path','d':'M21 16h-3a2 2 0 0 0-2 2v3'},{'_tag':'path','d':'M21 21v.01'},{'_tag':'path','d':'M12 7v3a2 2 0 0 1-2 2H7'},{'_tag':'path','d':'M3 12h.01'},{'_tag':'path','d':'M12 3h.01'},{'_tag':'path','d':'M12 16v.01'},{'_tag':'path','d':'M16 12h1'},{'_tag':'path','d':'M21 12v.01'},{'_tag':'path','d':'M12 21v-1'}],
  'receipt': [{'_tag':'path','d':'M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1-2-1z'},{'_tag':'path','d':'M16 8H8'},{'_tag':'path','d':'M16 12H8'},{'_tag':'path','d':'M12 16H8'}],
  'refresh-cw': [{'_tag':'path','d':'M3 2v6h6'},{'_tag':'path','d':'M21 12A9 9 0 0 0 6 5.3L3 8'},{'_tag':'path','d':'M21 22v-6h-6'},{'_tag':'path','d':'M3 12a9 9 0 0 0 15 6.7l3-2.7'}],
  'rss': [{'_tag':'path','d':'M4 11a9 9 0 0 1 9 9'},{'_tag':'path','d':'M4 4a16 16 0 0 1 16 16'},{'_tag':'circle','cx':'5','cy':'19','r':'1'}],
  'search': [{'_tag':'circle','cx':'11','cy':'11','r':'8'},{'_tag':'line','x1':'21','y1':'21','x2':'16.65','y2':'16.65'}],
  'send': [{'_tag':'line','x1':'22','y1':'2','x2':'11','y2':'13'},{'_tag':'polygon','points':'22 2 15 22 11 13 2 9 22 2'}],
  'shield-alert': [{'_tag':'path','d':'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'},{'_tag':'line','x1':'12','y1':'8','x2':'12','y2':'12'},{'_tag':'line','x1':'12','y1':'16','x2':'12.01','y2':'16'}],
  'shield-check': [{'_tag':'path','d':'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'},{'_tag':'path','d':'m9 12 2 2 4-4'}],
  'shopping-bag': [{'_tag':'path','d':'M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z'},{'_tag':'line','x1':'3','y1':'6','x2':'21','y2':'6'},{'_tag':'path','d':'M16 10a4 4 0 0 1-8 0'}],
  'sparkles': [{'_tag':'path','d':'m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z'},{'_tag':'path','d':'M5 3v4'},{'_tag':'path','d':'M19 17v4'},{'_tag':'path','d':'M3 5h4'},{'_tag':'path','d':'M17 19h4'}],
  'star': [{'_tag':'polygon','points':'12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2'}],
  'sun': [{'_tag':'circle','cx':'12','cy':'12','r':'4'},{'_tag':'path','d':'M12 2v2'},{'_tag':'path','d':'M12 20v2'},{'_tag':'path','d':'m4.93 4.93 1.41 1.41'},{'_tag':'path','d':'m17.66 17.66 1.41 1.41'},{'_tag':'path','d':'M2 12h2'},{'_tag':'path','d':'M20 12h2'},{'_tag':'path','d':'m6.34 17.66-1.41 1.41'},{'_tag':'path','d':'m19.07 4.93-1.41 1.41'}],
  'tag': [{'_tag':'path','d':'M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z'},{'_tag':'line','x1':'7','y1':'7','x2':'7.01','y2':'7'}],
  'terminal': [{'_tag':'polyline','points':'4 17 10 11 4 5'},{'_tag':'line','x1':'12','y1':'19','x2':'20','y2':'19'}],
  'trash-2': [{'_tag':'polyline','points':'3 6 5 6 21 6'},{'_tag':'path','d':'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2'},{'_tag':'line','x1':'10','y1':'11','x2':'10','y2':'17'},{'_tag':'line','x1':'14','y1':'11','x2':'14','y2':'17'}],
  'trending-up': [{'_tag':'polyline','points':'23 6 13.5 15.5 8.5 10.5 1 18'},{'_tag':'polyline','points':'17 6 23 6 23 12'}],
  'truck': [{'_tag':'rect','x':'1','y':'3','width':'15','height':'13'},{'_tag':'polygon','points':'16 8 20 8 23 11 23 16 16 16 16 8'},{'_tag':'circle','cx':'5.5','cy':'18.5','r':'2.5'},{'_tag':'circle','cx':'18.5','cy':'18.5','r':'2.5'}],
  'upload': [{'_tag':'polyline','points':'16 16 12 12 8 16'},{'_tag':'line','x1':'12','y1':'12','x2':'12','y2':'21'},{'_tag':'path','d':'M20.39 18.39A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.3'}],
  'upload-cloud': [{'_tag':'polyline','points':'16 16 12 12 8 16'},{'_tag':'line','x1':'12','y1':'12','x2':'12','y2':'21'},{'_tag':'path','d':'M20.39 18.39A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.3'}],
  'user': [{'_tag':'path','d':'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2'},{'_tag':'circle','cx':'12','cy':'7','r':'4'}],
  'user-plus': [{'_tag':'path','d':'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2'},{'_tag':'circle','cx':'9','cy':'7','r':'4'},{'_tag':'line','x1':'19','y1':'8','x2':'19','y2':'14'},{'_tag':'line','x1':'22','y1':'11','x2':'16','y2':'11'}],
  'users': [{'_tag':'path','d':'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2'},{'_tag':'circle','cx':'9','cy':'7','r':'4'},{'_tag':'path','d':'M23 21v-2a4 4 0 0 0-3-3.87'},{'_tag':'path','d':'M16 3.13a4 4 0 0 1 0 7.75'}],
  'wallet': [{'_tag':'path','d':'M20 12V8H6a2 2 0 0 1-2-2c0-1.1.9-2 2-2h12v4'},{'_tag':'path','d':'M4 6v12c0 1.1.9 2 2 2h14v-4'},{'_tag':'path','d':'M18 12a2 2 0 0 0 0 4h2v-4z'}],
  'wifi': [{'_tag':'path','d':'M5 12.55a11 11 0 0 1 14.08 0'},{'_tag':'path','d':'M1.42 9a16 16 0 0 1 21.16 0'},{'_tag':'path','d':'M8.53 16.11a6 6 0 0 1 6.95 0'},{'_tag':'line','x1':'12','y1':'20','x2':'12.01','y2':'20'}],
  'x': [{'_tag':'line','x1':'18','y1':'6','x2':'6','y2':'18'},{'_tag':'line','x1':'6','y1':'6','x2':'18','y2':'18'}],
  'x-circle': [{'_tag':'circle','cx':'12','cy':'12','r':'10'},{'_tag':'line','x1':'15','y1':'9','x2':'9','y2':'15'},{'_tag':'line','x1':'9','y1':'9','x2':'15','y2':'15'}],
  'zap': [{'_tag':'polygon','points':'13 2 3 14 12 14 11 22 21 10 12 10 13 2'}],
};

/// Logo component utilizing the new logo.png.
Component svgLogo({String size = 'w-8 h-8'}) {
  return img(
    src: '/images/logo.png',
    classes: '$size rounded-lg object-contain',
    attributes: {'alt': 'Tranyx Logo'},
  );
}

/// A high-fidelity inline SVG Google icon.
Component googleSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 24 24',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'd':
              'M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z',
          'fill': '#4285F4',
        },
        [],
      ),
      path(
        attributes: {
          'd':
              'M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z',
          'fill': '#34A853',
        },
        [],
      ),
      path(
        attributes: {
          'd':
              'M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z',
          'fill': '#FBBC05',
        },
        [],
      ),
      path(
        attributes: {
          'd':
              'M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z',
          'fill': '#EA4335',
        },
        [],
      ),
    ],
  );
}

/// A high-fidelity inline SVG Phantom Wallet icon.
Component phantomSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 32 32',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'fill-rule': 'evenodd',
          'clip-rule': 'evenodd',
          'd':
              'M21.2 12.3c-.6-.6-1.5-.9-2.5-1.1-2-.3-3.9.7-4.7 2.5l-.4 1c-.1.4-.6.6-1 .6-.9-.1-1.6.4-1.8 1.3-.1.7.3 1.4 1 1.6.4.1.6.4.6.8v3.8c0 .9.7 1.6 1.6 1.6.8 0 1.5-.6 1.6-1.4l.3-2.3c0-.4.4-.7.8-.7.4 0 .7.3.7.7l-.1 2.4c0 .9.6 1.7 1.6 1.7.9 0 1.7-.7 1.7-1.6l.2-4.8c0-.1 0-.3.1-.4.9-.9 2.1-1.4 3.4-1.4.8 0 1.5-.5 1.6-1.3.2-1.3-.5-2.6-1.8-2.9zM15.5 16.5c-.5 0-.9-.4-.9-.9s.4-.9.9-.9.9.4.9.9-.4.9-.9.9zm3.7 0c-.5 0-.9-.4-.9-.9s.4-.9.9-.9.9.4.9.9-.4.9-.9.9z',
          'fill': '#AB9FF2',
        },
        [],
      ),
    ],
  );
}

/// A high-fidelity inline SVG Solflare Wallet icon.
Component solflareSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 24 24',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'd': 'M12 2L14.85 8.15L21 11L14.85 13.85L12 20L9.15 13.85L3 11L9.15 8.15L12 2Z',
          'fill': '#FC8024',
        },
        [],
      ),
    ],
  );
}

/// A high-fidelity inline SVG Trust Wallet icon.
Component trustSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 24 24',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'd': 'M12 2L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-3zm0 18c-3.75-1.04-6.5-5.18-6.5-9.5V6.43l6.5-2.17 6.5 2.17V10.5c0 4.32-2.75 8.46-6.5 9.5z',
          'fill': '#3375BB',
        },
        [],
      ),
      path(
        attributes: {
          'd': 'M12 5.5l-4.5 1.5v3.5c0 2.8 1.8 5.5 4.5 6.5 2.7-1 4.5-3.7 4.5-6.5v-3.5L12 5.5z',
          'fill': '#3375BB',
        },
        [],
      ),
    ],
  );
}

/// A high-fidelity inline SVG Backpack Wallet icon.
Component backpackSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 24 24',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'd': 'M4 8c0-2.209 1.791-4 4-4h8c2.209 0 4 1.791 4 4v10c0 2.209-1.791 4-4 4H8c-2.209 0-4-1.791-4-4V8z',
          'stroke': '#E33E3F',
          'stroke-width': '2',
        },
        [],
      ),
      path(
        attributes: {
          'd': 'M9 4V2.5c0-.828.672-1.5 1.5-1.5h3c.828 0 1.5.672 1.5 1.5V4',
          'stroke': '#E33E3F',
          'stroke-width': '2',
        },
        [],
      ),
      path(
        attributes: {
          'd': 'M4 11h16M8 15h8M12 11v4',
          'stroke': '#E33E3F',
          'stroke-width': '2',
        },
        [],
      ),
    ],
  );
}

/// Styled text input field with optional label and leading icon.
Component inputField({
  String label = '',
  String placeholder = '',
  String iconName = '',
  String type = 'text',
  String value = '',
  bool isDark = true,
  void Function(String)? onChange,
  bool isPassword = false,
  bool isPasswordVisible = false,
  void Function()? onTogglePassword,
}) {
  final borderCls = isDark
      ? 'bg-zinc-900 border-zinc-800 focus-within:border-indigo-500'
      : 'bg-white border-zinc-200 focus-within:border-indigo-500 shadow-sm';

  final inputId = label.isNotEmpty
      ? label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      : 'input_${placeholder.hashCode}';

  return div(classes: 'p-4 rounded-2xl border transition-colors $borderCls', [
    if (label.isNotEmpty)
      span(
        classes: 'block text-xs font-medium mb-1 ${isDark ? 'text-zinc-500' : 'text-zinc-400'}',
        [Component.text(label)],
      ),
    div(classes: 'flex items-center justify-between', [
      div(classes: 'flex items-center flex-1', [
        if (iconName.isNotEmpty) lIcon(iconName, cls: 'w-5 h-5 mr-3 ${isDark ? 'text-zinc-600' : 'text-zinc-400'}'),
        input<String>(
          classes:
              'bg-transparent border-none outline-none w-full text-sm md:text-base font-medium ${isDark ? 'text-zinc-200' : 'text-zinc-900'}',
          type: (isPassword && isPasswordVisible)
              ? InputType.text
              : (type == 'password' ? InputType.password : (type == 'email' ? InputType.email : InputType.text)),
          value: value,
          attributes: {
            'placeholder': placeholder,
            'value': value,
            if (type == 'date') 'type': 'date',
            'id': inputId,
            'name': inputId,
          },
          onInput: onChange,
        ),
      ]),
      if (isPassword && onTogglePassword != null)
        button(
          classes: 'p-1 rounded-lg hover:bg-zinc-500/10 focus:outline-none ml-2 transition-colors cursor-pointer border-0',
          events: {'click': (_) => onTogglePassword()},
          [
            lIcon(
              isPasswordVisible ? 'eye-off' : 'eye',
              cls: 'w-4 h-4 ${isDark ? 'text-zinc-500 hover:text-zinc-300' : 'text-zinc-400 hover:text-zinc-600'}',
            ),
          ],
        ),
    ]),
  ]);
}

/// Pill/tag label.
Component tagChip(String label, bool isDark) {
  return span(
    classes:
        'px-4 py-2 rounded-lg text-sm font-medium ${isDark ? 'bg-zinc-800 text-zinc-300' : 'bg-zinc-100 text-zinc-700'}',
    [Component.text(label)],
  );
}

/// Badge with custom classes.
Component badge(String label, String cls) {
  return span(
    classes: 'px-2.5 py-1 rounded-md text-[10px] font-bold uppercase tracking-wider $cls',
    [Component.text(label)],
  );
}

/// Account type badge.
Component accountBadge(String acType) {
  final cls = acType == 'hybrid'
      ? 'bg-amber-500/20 text-amber-500'
      : acType == 'employer'
      ? 'bg-blue-500/20 text-blue-500'
      : 'bg-green-500/20 text-green-500';
  final label = acType == 'nyxian' ? 'Nyxian Worker' : '${acType[0].toUpperCase()}${acType.substring(1)} View';
  return badge(label, cls);
}

/// Sub-view header with back button and title.
Component subViewHeader({
  required String title,
  required bool isDark,
  required void Function() onBack,
}) {
  return div(classes: 'flex items-center gap-4 mb-8', [
    button(
      classes:
          'p-2 rounded-full transition-all border flex items-center justify-center '
          '${isDark ? "bg-zinc-800/80 border-zinc-700/60 text-zinc-300 hover:bg-zinc-750 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-600 hover:bg-zinc-150 hover:text-zinc-800"}',
      events: {'click': (_) => onBack()},
      [lIcon('arrow-left', cls: 'w-5 h-5')],
    ),
    h2(classes: 'text-2xl md:text-3xl font-extrabold tracking-tight', [Component.text(title)]),
  ]);
}

/// Verification row item.
Component verificationItem({required String title, required String status, required bool isDark}) {
  final verified = status == 'Verified';
  return div(
    classes:
        'flex items-center justify-between p-5 rounded-2xl border ${isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm'}',
    [
      span(
        classes: 'font-medium text-base ${isDark ? 'text-zinc-200' : 'text-zinc-800'}',
        [Component.text(title)],
      ),
      if (verified)
        span(
          classes: 'flex items-center gap-1.5 text-xs font-bold text-green-500 bg-green-500/10 px-3 py-1.5 rounded-md',
          [lIcon('shield-check', cls: 'w-4 h-4'), Component.text(' VERIFIED')],
        )
      else
        span(
          classes: 'text-xs font-bold text-amber-500 bg-amber-500/10 px-3 py-1.5 rounded-md',
          [Component.text('PENDING')],
        ),
    ],
  );
}

/// FAQ row button.
Component supportFaq({required String title, String iconName = 'file-text', required bool isDark}) {
  return button(
    classes:
        'w-full flex items-center justify-between p-5 rounded-2xl border transition-all text-left ${isDark ? 'bg-zinc-900 border-zinc-800 hover:bg-zinc-800' : 'bg-white border-zinc-200 shadow-sm hover:shadow-md'}',
    [
      div(classes: 'flex items-center gap-4', [
        lIcon(iconName, cls: 'w-5 h-5 ${isDark ? 'text-zinc-500' : 'text-zinc-400'}'),
        span(
          classes: 'font-medium text-base ${isDark ? 'text-zinc-200' : 'text-zinc-800'}',
          [Component.text(title)],
        ),
      ]),
      lIcon('chevron-right', cls: 'w-5 h-5 ${isDark ? 'text-zinc-700' : 'text-zinc-300'}'),
    ],
  );
}

/// Segmented control — pass selected value and list of (label, value) pairs.
Component segmentedControl({
  required List<(String label, String value)> options,
  required String selected,
  required bool isDark,
  required void Function(String) onChange,
}) {
  return div(
    classes:
        'flex p-1 rounded-2xl ${isDark ? 'bg-zinc-900 border border-zinc-800' : 'bg-zinc-100 border border-zinc-200'}',
    [
      for (final opt in options)
        button(
          classes:
              'flex-1 py-2.5 text-xs font-semibold rounded-xl transition-all ${selected == opt.$2 ? (isDark ? 'bg-zinc-800 text-white shadow-sm' : 'bg-white text-zinc-900 shadow-sm') : (isDark ? 'text-zinc-500 hover:text-zinc-300' : 'text-zinc-500 hover:text-zinc-700')}',
          events: {'click': (_) => onChange(opt.$2)},
          [Component.text(opt.$1)],
        ),
    ],
  );
}

/// Normalizes any category string (camelCase, snake_case, spaces, etc.) 
/// to a title-cased string with spaces (e.g. "curtainInstaller" -> "Curtain Installer").
String normalizeCategoryName(String cat) {
  if (cat.isEmpty) return '';
  
  // Replace underscores, hyphens, and slashes with spaces
  String temp = cat.replaceAll(RegExp(r'[_/\-]'), ' ');
  
  // Insert spaces before capital letters (for CamelCase)
  final buffer = StringBuffer();
  for (var i = 0; i < temp.length; i++) {
    final char = temp[i];
    if (i > 0 && 
        char.codeUnitAt(0) >= 65 && char.codeUnitAt(0) <= 90 && // Capital letter
        temp[i-1] != ' ' && 
        !(temp[i-1].codeUnitAt(0) >= 65 && temp[i-1].codeUnitAt(0) <= 90)) {
      buffer.write(' ');
    }
    buffer.write(char);
  }
  temp = buffer.toString();
  
  // Split by spaces, capitalize each word, and join
  final words = temp.split(' ').where((w) => w.isNotEmpty);
  return words.map((w) {
    if (w.isEmpty) return '';
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
}
