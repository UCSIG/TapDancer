import 'package:material_ui/material_ui.dart';
import 'package:tapdancer/utils/app_theme.dart';

class AppContainer {
  static BoxDecoration surface({bool isActive = false}) {
    return BoxDecoration(
      color: isActive ? AppColor.surfaceSecondary : AppColor.surfacePrimary,
      borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
      border: Border.all(
        color: isActive ? AppColor.primary.withValues(alpha: 0.6) : AppColor.border,
        width: AppColor.borderWidth,
      ),
      boxShadow: isActive
          ? [
              BoxShadow(
                color: AppColor.primary.withValues(alpha: 0.12),
                blurRadius: 16,
                spreadRadius: -2,
              )
            ]
          : null,
    );
  }

  static BoxDecoration header({bool hasBlur = true}) {
    return BoxDecoration(
      color: AppColor.bgColor,
      backgroundBlendMode: hasBlur ? BlendMode.srcOver : null,
    );
  }

  static BoxDecoration statusBadge(Color color) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(AppSizing.radiusXXLarge),
    );
  }

  static BoxDecoration button({
    required bool isActive,
    Gradient? gradient,
    Color? backgroundColor,
  }) {
    return BoxDecoration(
      gradient: gradient,
      color: backgroundColor,
      border: isActive ? Border.all(color: AppColor.success.withValues(alpha: 0.5)) : null,
      borderRadius: BorderRadius.circular(AppSizing.radiusLarge),
    );
  }
}
