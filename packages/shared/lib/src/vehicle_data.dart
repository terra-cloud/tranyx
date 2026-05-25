import 'enums.dart';

class VehicleSpecDatabase {
  static const Map<VehicleType, Map<String, List<String>>>
  modelsByTypeAndBrand = {
    VehicleType.car: {
      'Toyota': ['Vios', 'Wigo', 'Corolla Altis', 'Camry', 'Yaris', 'Prius'],
      'Honda': ['Civic', 'City', 'Brio', 'Accord'],
      'Mitsubishi': ['Mirage G4', 'Mirage Hatchback'],
      'Nissan': ['Almera', 'Sylphy'],
      'Hyundai': ['Accent', 'Elantra', 'Ioniq 5'],
      'Suzuki': ['Dzire', 'Swift', 'Celerio'],
      'Mazda': ['Mazda 3', 'Mazda 2', 'Mazda 6'],
      'Kia': ['Soluto', 'Rio'],
    },
    VehicleType.suv: {
      'Toyota': [
        'Fortuner',
        'Land Cruiser',
        'RAV4',
        'Rush',
        'Corolla Cross',
        'Raize',
        'Prado',
      ],
      'Honda': ['CR-V', 'HR-V', 'BR-V'],
      'Mitsubishi': ['Montero Sport', 'Outlander', 'Pajero'],
      'Ford': ['Everest', 'Territory', 'Explorer'],
      'Nissan': ['Terra', 'Patrol', 'X-Trail'],
      'Hyundai': ['Tucson', 'Santa Fe', 'Creta', 'Palisade'],
      'Isuzu': ['mu-X'],
      'Chevrolet': ['Trailblazer', 'Suburban'],
    },
    VehicleType.van: {
      'Toyota': ['Hiace', 'Alphard', 'Avanza', 'Veloz', 'Innova'],
      'Nissan': ['NV350 Urvan'],
      'Hyundai': ['Starex', 'Staria'],
      'Mitsubishi': ['L300', 'Adventure'],
      'Kia': ['Carnival'],
      'Foton': ['Transvan'],
      'Honda': ['Odyssey'],
    },
    VehicleType.truck: {
      'Toyota': ['Hilux'],
      'Mitsubishi': ['Triton', 'Strada'],
      'Ford': ['Ranger', 'Ranger Raptor', 'F-150'],
      'Nissan': ['Navara'],
      'Isuzu': ['D-Max'],
      'Chevrolet': ['Colorado'],
      'Mazda': ['BT-50'],
    },
    VehicleType.motorcycle: {
      'Honda': [
        'Click 125i',
        'Beat',
        'ADV 160',
        'PCX 160',
        'CBR150R',
        'Wave 110',
        'TMX 125',
      ],
      'Yamaha': [
        'NMAX',
        'Aerox',
        'Mio Sporty',
        'Sniper 155',
        'XMAX',
        'Fazzio',
        'Gravis',
      ],
      'Suzuki': ['Raider R150', 'Burgman Street', 'Smash', 'Gixxer', 'Address'],
      'Kawasaki': ['Ninja 400', 'Barako II', 'W175', 'Rouser NS200'],
      'Vespa': ['Primavera', 'GTS 300', 'Sprint 150', 'S 125'],
      'Kymco': ['Like 150i', 'KRV 180', 'Super 8'],
    },
  };

  static List<int> getYearsForModel(String model) {
    // Generate years from 2015 to 2026 as standard for all listed models
    return List<int>.generate(12, (index) => 2026 - index);
  }
}
