import 'package:flutter/material.dart';

import 'andean_theme.dart';

abstract final class EditorialColors {
  static const canvas = Color(0xFFF7F5F0);
  static const paper = Color(0xFFFFFDF9);
  static const line = Color(0xFFE7E0D4);
  static const sand = Color(0xFFEEE8DC);
  static const accent = Color(0xFF765A39);
}

class EditorialEmblem extends StatelessWidget {
  const EditorialEmblem(this.icon, {super.key, this.dark = false});

  final IconData icon;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: dark ? AndeanColors.primaryBrand : EditorialColors.sand,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(
      icon,
      size: 21,
      color: dark ? AndeanColors.onPrimary : AndeanColors.primaryBrand,
    ),
  );
}
