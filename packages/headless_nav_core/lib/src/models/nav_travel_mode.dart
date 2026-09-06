/// Travel modes supported for routing, speed profiles, and vehicle representations.
enum NavTravelMode {
  car('car', 'routed-car', 'driving', 'car-15', 'Car'),
  motorcycle('motorcycle', 'routed-car', 'driving', 'motorcycle-15', 'Motorcycle'),
  bike('bike', 'routed-bike', 'bicycle', 'bicycle-15', 'Bicycle'),
  foot('foot', 'routed-foot', 'walking', 'walk-15', 'Walking');

  final String id;
  final String fossgisServerSlug;
  final String osrmMode;
  final String defaultIcon;
  final String label;

  const NavTravelMode(
    this.id,
    this.fossgisServerSlug,
    this.osrmMode,
    this.defaultIcon,
    this.label,
  );

  String toJson() => id;

  static NavTravelMode fromJson(String value) {
    return NavTravelMode.values.firstWhere(
      (m) => m.id == value || m.name == value,
      orElse: () => NavTravelMode.car,
    );
  }
}
