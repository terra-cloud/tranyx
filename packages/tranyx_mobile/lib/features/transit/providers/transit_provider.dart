import 'package:flutter_riverpod/legacy.dart';
import 'package:shared/shared.dart';

final transitModeProvider = StateProvider<String>((ref) => 'rent');

final activeRentalCategoryProvider = StateProvider<String>((ref) => 'vehicles');

final transitSearchQueryProvider = StateProvider<String>((ref) => '');

final transitMaxPriceProvider = StateProvider<double?>((ref) => null);

final transitDurationFilterProvider = StateProvider<String>((ref) => 'any');

final transitSelectedPropertyCategoryProvider =
    StateProvider<PropertyCategory?>((ref) => null);

final transitSelectedPropertyTypeProvider = StateProvider<PropertyType?>(
  (ref) => null,
);

final transitGeofenceRadiusProvider = StateProvider<double>((ref) => 30.0);
