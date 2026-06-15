import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF8F7F2);
  static const surface = Color(0xFFFAF9F5);
  static const searchFill = Color(0xFFE9E7E1);
  static const primary = Color(0xFF6A9C89);
  static const primaryDark = Color(0xFF4F7E6C);
  static const secondary = Color(0xFFFFD66B);
  static const text = Color(0xFF2F2F2F);
  static const mutedText = Color(0xFF6F6F6F);
  static const card = Color(0xFFFFFFFF);
  static const error = Color(0xFFE57373);
  static const ink = Color(0xFF242424);
  static const border = Color(0xFFE4E0D7);
  static const disabled = Color(0xFFBDB8AD);
  static const darkBackground = Color(0xFF161817);
  static const darkSurface = Color(0xFF202421);
  static const darkCard = Color(0xFF252B27);
  static const darkSearchFill = Color(0xFF303630);
  static const darkText = Color(0xFFF3F1EA);
  static const darkMutedText = Color(0xFFC0BDB4);
  static const darkBorder = Color(0xFF3D443F);

  static const noteColors = [
    Color(0xFFCFE6FF),
    Color(0xFFFFC5D7),
    Color(0xFFD6F8D4),
    Color(0xFFFFEDAD),
    Color(0xFFFFD5C8),
    Color(0xFFD9CCFF),
  ];

  static const darkNoteColors = [
    Color(0xFF24425E),
    Color(0xFF5B2B3B),
    Color(0xFF294C35),
    Color(0xFF5A4822),
    Color(0xFF56372D),
    Color(0xFF3D315E),
  ];

  static Color noteColorFor(Brightness brightness, int index) {
    final palette = brightness == Brightness.dark ? darkNoteColors : noteColors;
    return palette[index % palette.length];
  }
}
