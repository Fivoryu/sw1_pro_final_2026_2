import 'package:flutter/material.dart';

import 'andean_theme.dart';

/// Preset variants for Andean notice banners
enum AndeanBannerVariant {
  institutional,
  warning,
  success,
  critical,
  info,
  demo,
}

/// Architectural candor notice card following Andean design guidelines
class AndeanNoticeBanner extends StatelessWidget {
  const AndeanNoticeBanner({
    super.key,
    required this.message,
    this.title,
    this.badge,
    this.icon,
    this.variant = AndeanBannerVariant.institutional,
  });

  final String message;
  final String? title;
  final String? badge;
  final IconData? icon;
  final AndeanBannerVariant variant;

  @override
  Widget build(BuildContext context) {
    final (bg, textColor, defaultIcon) = switch (variant) {
      AndeanBannerVariant.institutional => (
        AndeanColors.surfaceContainerHigh,
        AndeanColors.onSurface,
        Icons.terminal,
      ),
      AndeanBannerVariant.warning => (
        AndeanColors.warningBg,
        AndeanColors.warningText,
        Icons.warning_amber_rounded,
      ),
      AndeanBannerVariant.success => (
        AndeanColors.successBg,
        AndeanColors.successText,
        Icons.check_circle_outline,
      ),
      AndeanBannerVariant.critical => (
        AndeanColors.criticalBg,
        AndeanColors.criticalText,
        Icons.error_outline,
      ),
      AndeanBannerVariant.info => (
        AndeanColors.infoBg,
        AndeanColors.infoText,
        Icons.info_outline,
      ),
      AndeanBannerVariant.demo => (
        AndeanColors.demoBadgeBg,
        AndeanColors.demoBadgeText,
        Icons.science_outlined,
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AndeanColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 20, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null || badge != null) ...[
                  Row(
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: AndeanTypography.labelMd.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AndeanColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            badge!,
                            style: AndeanTypography.labelSm.copyWith(
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  message,
                  style: AndeanTypography.bodySm.copyWith(
                    color: textColor.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill status chip
class AndeanPillChip extends StatelessWidget {
  const AndeanPillChip({
    super.key,
    required this.label,
    this.backgroundColor = AndeanColors.surfaceContainer,
    this.textColor = AndeanColors.onSurfaceVariant,
    this.icon,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(9999),
      border: Border.all(color: AndeanColors.border, width: 0.8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: AndeanTypography.labelSm.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
