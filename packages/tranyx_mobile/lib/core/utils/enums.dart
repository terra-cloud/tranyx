import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared/shared.dart';

export 'package:shared/src/enums.dart';

extension JobCategoryExtension on JobCategory {
  IconData get iconData {
    switch (icon) {
      case 'zap':
        return LucideIcons.zap;
      case 'droplet':
      case 'droplets':
        return LucideIcons.droplets;
      case 'hammer':
        return LucideIcons.hammer;
      case 'paintbrush':
        return LucideIcons.paintbrush;
      case 'wrench':
        return LucideIcons.wrench;
      case 'layout-grid':
        return LucideIcons.layoutGrid;
      case 'home':
      case 'house':
        return LucideIcons.house;
      case 'wind':
        return LucideIcons.wind;
      case 'bug':
        return LucideIcons.bug;
      case 'key':
        return LucideIcons.key;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'shirt':
        return LucideIcons.shirt;
      case 'car':
        return LucideIcons.car;
      case 'package':
        return LucideIcons.package;
      case 'truck':
        return LucideIcons.truck;
      case 'file-text':
        return LucideIcons.fileText;
      case 'utensils':
        return LucideIcons.utensils;
      case 'activity':
        return LucideIcons.activity;
      case 'person-standing':
        return LucideIcons.personStanding;
      case 'map-pin':
      case 'map':
        return LucideIcons.map;
      case 'heart':
        return LucideIcons.heart;
      case 'book-open':
        return LucideIcons.bookOpen;
      case 'user':
        return LucideIcons.user;
      case 'monitor':
        return LucideIcons.monitor;
      case 'phone':
        return LucideIcons.phone;
      case 'camera':
        return LucideIcons.camera;
      case 'pen-tool':
        return LucideIcons.penTool;
      case 'message-square':
        return LucideIcons.messageSquare;
      case 'scissors':
        return LucideIcons.scissors;
      case 'brush':
        return LucideIcons.brush;
      case 'hand':
        return LucideIcons.hand;
      case 'dumbbell':
        return LucideIcons.dumbbell;
      case 'brain':
        return LucideIcons.brain;
      case 'party-popper':
        return LucideIcons.partyPopper;
      case 'archive':
        return LucideIcons.archive;
      case 'square-split-vertical':
        return LucideIcons.squareSplitVertical;
      case 'trash':
        return LucideIcons.trash;
      case 'container':
        return LucideIcons.container;
      case 'calendar':
        return LucideIcons.calendar;
      case 'code':
        return LucideIcons.code;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'hexagon':
        return LucideIcons.hexagon;
      case 'calculator':
        return LucideIcons.calculator;
      case 'shield':
        return LucideIcons.shield;
      case 'briefcase':
        return LucideIcons.briefcase;
      case 'search':
        return LucideIcons.search;
      case 'trending-up':
        return LucideIcons.trendingUp;
      case 'pen':
        return LucideIcons.pen;
      case 'check':
        return LucideIcons.check;
      case 'star':
        return LucideIcons.star;
      case 'mail':
        return LucideIcons.mail;
      case 'scale':
        return LucideIcons.scale;
      case 'building':
        return LucideIcons.building;
      case 'graduation-cap':
        return LucideIcons.graduationCap;
      case 'stethoscope':
        return LucideIcons.stethoscope;
      case 'headset':
        return LucideIcons.headset;
      case 'users':
        return LucideIcons.users;
      default:
        return LucideIcons.briefcase;
    }
  }
}

extension JobCategoryGroupExtension on JobCategoryGroup {
  IconData get iconData {
    switch (icon) {
      case 'hammer':
        return LucideIcons.hammer;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'flower-2':
        return LucideIcons.flower2;
      case 'wrench':
        return LucideIcons.wrench;
      case 'package':
        return LucideIcons.package;
      case 'truck':
        return LucideIcons.truck;
      case 'heart':
        return LucideIcons.heart;
      case 'monitor':
        return LucideIcons.monitor;
      case 'trending-up':
        return LucideIcons.trendingUp;
      case 'palette':
        return LucideIcons.palette;
      case 'scale':
        return LucideIcons.scale;
      case 'graduation-cap':
        return LucideIcons.graduationCap;
      case 'stethoscope':
        return LucideIcons.stethoscope;
      case 'headset':
        return LucideIcons.headset;
      default:
        return LucideIcons.briefcase;
    }
  }

  Color get colorValue {
    switch (color) {
      case 'text-amber-600':
        return Colors.amber.shade600;
      case 'text-indigo-500':
        return Colors.indigo.shade500;
      case 'text-green-600':
        return Colors.green.shade600;
      case 'text-sky-500':
        return const Color(0xFF0ea5e9);
      case 'text-orange-500':
        return Colors.orange.shade500;
      case 'text-blue-600':
        return Colors.blue.shade600;
      case 'text-pink-500':
        return Colors.pink.shade500;
      case 'text-blue-500':
        return Colors.blue.shade500;
      case 'text-emerald-600':
        return const Color(0xFF059669);
      case 'text-purple-500':
        return Colors.purple.shade500;
      case 'text-rose-500':
        return const Color(0xFFf43f5e);
      case 'text-zinc-700':
        return Colors.grey.shade700;
      case 'text-amber-500':
        return Colors.amber.shade500;
      case 'text-red-500':
        return Colors.red.shade500;
      case 'text-zinc-500':
        return Colors.grey.shade500;
      default:
        return Colors.grey;
    }
  }

  static Map<JobCategoryGroup, List<JobCategory>> get categoryMap {
    final map = <JobCategoryGroup, List<JobCategory>>{};
    for (final group in JobCategoryGroup.values) {
      map[group] = group.categories;
    }
    return map;
  }
}
