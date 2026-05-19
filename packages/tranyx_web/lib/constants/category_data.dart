import 'package:shared/shared.dart';

extension JobCategoryGroupWebExtension on JobCategoryGroup {
  String get tailwindColor => switch (this) {
    JobCategoryGroup.homeRepair => 'bg-amber-500/10 text-amber-500',
    JobCategoryGroup.cleaning => 'bg-indigo-500/10 text-indigo-500',
    JobCategoryGroup.outdoor => 'bg-green-500/10 text-green-500',
    JobCategoryGroup.automotive => 'bg-sky-500/10 text-sky-500',
    JobCategoryGroup.delivery => 'bg-orange-500/10 text-orange-500',
    JobCategoryGroup.moving => 'bg-blue-500/10 text-blue-500',
    JobCategoryGroup.personalCare => 'bg-pink-500/10 text-pink-500',
    JobCategoryGroup.tech => 'bg-blue-500/10 text-blue-500',
    JobCategoryGroup.business => 'bg-emerald-500/10 text-emerald-500',
    JobCategoryGroup.creative => 'bg-purple-500/10 text-purple-500',
    JobCategoryGroup.marketing => 'bg-rose-500/10 text-rose-500',
    JobCategoryGroup.professional => 'bg-zinc-500/10 text-zinc-400',
    JobCategoryGroup.education => 'bg-amber-500/10 text-amber-500',
    JobCategoryGroup.health => 'bg-red-500/10 text-red-500',
    JobCategoryGroup.support => 'bg-blue-500/10 text-blue-500',
    JobCategoryGroup.miscellaneousEvents => 'bg-zinc-500/10 text-zinc-400',
  };
}

final categoryMap = {
  for (var group in JobCategoryGroup.values) group: group.categories,
};
