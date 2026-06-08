import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';

class UIHelpers {
  static Widget buildTextField(
    IconData icon,
    String hint,
    bool isDarkMode, {
    bool isPassword = false,
    TextEditingController? controller,
    Function(String)? onChanged,
    Function(String)? onSubmitted,
    List<dynamic>? inputFormatters,
    TextInputType? keyboardType,
    int? maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF121214) : AppColors.lightBg,
        border: Border.all(
          color: isDarkMode ? const Color(0xFF1E1E20) : AppColors.lightBorder,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        maxLines: isPassword ? 1 : maxLines,
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: isPassword,
        inputFormatters: inputFormatters != null
            ? List<TextInputFormatter>.from(inputFormatters)
            : null,
        keyboardType: keyboardType,
        style: TextStyle(
          color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          icon: Icon(
            icon,
            color: isDarkMode
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
            size: 20,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: isDarkMode
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
            fontSize: 14,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  static Widget buildPrimaryButton(
    String text,
    VoidCallback? onPressed,
    bool isDarkMode, {
    bool isOutlined = false,
  }) {
    return Container(
      decoration: !isOutlined
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            )
          : null,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isOutlined ? Colors.transparent : AppColors.indigo,
          foregroundColor: isOutlined
              ? (isDarkMode ? AppColors.darkText : AppColors.lightText)
              : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: isOutlined
                ? BorderSide(
                    color: isDarkMode
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                    width: 2,
                  )
                : BorderSide.none,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
