import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';

class UserAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;
  final double radius;
  final BoxBorder? border;
  final Color? backgroundColor;
  final TextStyle? textStyle;

  const UserAvatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.radius = 20,
    this.border,
    this.backgroundColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty && photoUrl != 'null';
    
    // Get the initial(s) of the name (up to 2 characters)
    String initials = '?';
    if (name != null && name!.trim().isNotEmpty) {
      final parts = name!.trim().split(RegExp(r'\s+'));
      if (parts.length > 1) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else if (parts[0].isNotEmpty) {
        initials = parts[0][0].toUpperCase();
      }
    }

    final double size = radius * 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: hasPhoto ? null : (backgroundColor ?? AppColors.indigo),
        image: hasPhoto
            ? DecorationImage(
                image: NetworkImage(photoUrl!),
                fit: BoxFit.cover,
                onError: (_, __) {
                  // Fallback on image loading error will be handled by the framework 
                  // but we want to make sure it doesn't crash.
                },
              )
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                initials,
                style: textStyle ??
                    TextStyle(
                      color: Colors.white,
                      fontSize: radius * 0.7,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
    );
  }
}
