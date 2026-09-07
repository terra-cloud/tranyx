import 'dart:js_interop';

/// Type-safe Dart JS Interop bindings for MapLibre GL JS.
@JS('maplibregl.Map')
extension type MapLibreMap._(JSObject _) implements JSObject {
  external factory MapLibreMap(MapOptions options);

  external void on(JSString event, JSFunction callback);
  external void remove();
  external void setStyle(JSString style);
  external void easeTo(EaseToOptions options);
  external void flyTo(FlyToOptions options);
  external GeoJSONSource? getSource(JSString id);
  external void addSource(JSString id, JSObject sourceDef);
  external void addLayer(JSObject layerDef);
  external void resize();
  external JSBoolean isStyleLoaded();
  external void setPaintProperty(JSString layerId, JSString name, JSAny value);
}

@JS()
@anonymous
extension type MapPadding._(JSObject _) implements JSObject {
  external factory MapPadding({
    JSNumber? top,
    JSNumber? bottom,
    JSNumber? left,
    JSNumber? right,
  });
}

@JS()
@anonymous
extension type MapOptions._(JSObject _) implements JSObject {
  external factory MapOptions({
    JSString container,
    JSString style,
    JSArray<JSNumber> center,
    JSNumber zoom,
    JSNumber pitch,
    JSNumber bearing,
    MapPadding? padding,
    JSBoolean? attributionControl,
    JSBoolean? interactive,
    JSBoolean? dragPan,
    JSBoolean? scrollZoom,
    JSBoolean? dragRotate,
    JSBoolean? doubleClickZoom,
    JSBoolean? boxZoom,
  });
}

@JS()
@anonymous
extension type EaseToOptions._(JSObject _) implements JSObject {
  external factory EaseToOptions({
    JSArray<JSNumber>? center,
    JSNumber? zoom,
    JSNumber? bearing,
    JSNumber? pitch,
    JSNumber? duration,
    MapPadding? padding,
  });
}

@JS()
@anonymous
extension type FlyToOptions._(JSObject _) implements JSObject {
  external factory FlyToOptions({
    JSArray<JSNumber>? center,
    JSNumber? zoom,
    JSNumber? bearing,
    JSNumber? pitch,
    JSNumber? duration,
    MapPadding? padding,
  });
}

@JS('maplibregl.Marker')
extension type MapLibreMarker._(JSObject _) implements JSObject {
  external factory MapLibreMarker([JSObject? options]);

  external MapLibreMarker setLngLat(JSArray<JSNumber> lngLat);
  external MapLibreMarker setRotation(JSNumber rotation);
  external MapLibreMarker addTo(MapLibreMap map);
  external void remove();
}

@JS()
@anonymous
extension type GeoJSONSource._(JSObject _) implements JSObject {
  external void setData(JSAny data);
}
