import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A component that renders a map container `div`.
/// Overrides [shouldRebuild] to return `false`, which ensures that once the element is mounted,
/// Jaspr will not diff it or recreate it on state updates, allowing MapLibre to control its DOM safely.
class MapContainer extends StatelessComponent {
  final String id;
  final String? classes;
  final Styles? styles;

  const MapContainer({
    required this.id,
    this.classes,
    this.styles,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      id: id,
      classes: classes,
      styles: styles,
      [],
    );
  }

  @override
  bool shouldRebuild(covariant MapContainer newComponent) => false;
}
