import 'package:flutter/material.dart';

class AppColors {
  static const star = Color(0xFF9A6200);
  static const darkStar = Color(0xFFE8A93A);
  static const controlOutline = Color(0xFF7A766E);
  static const darkControlOutline = Color(0xFF7E8680);

  static Color starFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkStar : star;
  static const darkPrimary = Color(0xFF86B7A3);
  static const colorKeys = ['blue', 'pink', 'mint', 'yellow', 'peach', 'lav'];
  static Color noteColor(Brightness brightness, String key) {
    final index = colorKeys.indexOf(key);
    if (index < 0) {
      return brightness == Brightness.dark ? darkSurface : surface;
    }
    return noteColorFor(brightness, index);
  }

  static const background = Color(0xFFF8F7F2);
  static const surface = Color(0xFFFFFFFF);
  static const searchFill = Color(0xFFEFEDE5);
  static const primary = Color(0xFF497665);
  static const primaryDark = primary;
  static const secondary = Color(0xFFFFD66B);
  static const text = Color(0xFF2F2F2F);
  static const mutedText = Color(0xFF666662);
  static const card = Color(0xFFFFFFFF);
  static const error = Color(0xFFB83B3B);
  static const darkError = Color(0xFFE57373);
  static const ink = Color(0xFF2F2F2F);
  static const border = Color(0xFFE4E0D7);
  static const disabled = Color(0xFFBDB8AD);
  static const darkBackground = Color(0xFF1B1E1C);
  static const darkSurface = Color(0xFF242926);
  static const darkCard = Color(0xFF242926);
  static const darkSearchFill = Color(0xFF2C322E);
  static const darkText = Color(0xFFF1EEE4);
  static const darkMutedText = Color(0xFFA3A89F);
  static const darkBorder = Color(0xFF343A36);

  static const noteColors = [
    Color(0xFFCFE6FF),
    Color(0xFFFFC5D7),
    Color(0xFFD6F8D4),
    Color(0xFFFFEDAD),
    Color(0xFFFFD5C8),
    Color(0xFFD9CCFF),
  ];

  static const darkNoteColors = [
    Color(0xFF2F3C48),
    Color(0xFF47343B),
    Color(0xFF2F4232),
    Color(0xFF45402B),
    Color(0xFF48372F),
    Color(0xFF3A3549),
  ];

  static Color noteColorFor(Brightness brightness, int index) {
    final palette = brightness == Brightness.dark ? darkNoteColors : noteColors;
    return palette[index % palette.length];
  }
}
