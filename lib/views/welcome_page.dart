import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_routes.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/custom_button.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SafeArea(
            child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const NotedBrand(size: 30),
                                  SizedBox(
                                      height: (box.maxHeight - 390)
                                          .clamp(220.0, 420.0),
                                      width: double.infinity,
                                      child: const _HeroStage()),
                                  Text.rich(
                                      TextSpan(
                                          text: 'A peaceful space for ',
                                          children: [
                                            TextSpan(
                                                text: 'powerful thinking.',
                                                style: TextStyle(
                                                    fontFamily: 'Newsreader',
                                                    fontStyle: FontStyle.italic,
                                                    fontWeight: FontWeight.w400,
                                                    color: Theme.of(context)
                                                                .brightness ==
                                                            Brightness.dark
                                                        ? AppColors.darkPrimary
                                                        : AppColors
                                                            .primaryDark))
                                          ]),
                                      style: const TextStyle(
                                          fontSize: 34,
                                          fontWeight: FontWeight.w600,
                                          height: 1.08,
                                          letterSpacing: -1.02)),
                                  const SizedBox(height: 12),
                                  Text(
                                      'Capture ideas, find them instantly, and write together with the people you learn with.',
                                      style: TextStyle(
                                          fontSize: 15,
                                          height: 1.55,
                                          color: Theme.of(context).hintColor)),
                                  const SizedBox(height: 28),
                                  CustomButton(
                                      label: 'Create an account',
                                      onPressed: () => Navigator.pushNamed(
                                          context, AppRoutes.signUp)),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: TextButton(
                                          onPressed: () => Navigator.pushNamed(
                                              context, AppRoutes.signIn),
                                          child: Text.rich(TextSpan(
                                              text: 'Already have an account? ',
                                              style: TextStyle(
                                                  fontSize: 15,
                                                  color: Theme.of(context)
                                                      .hintColor),
                                              children: [
                                                TextSpan(
                                                    text: 'Sign in',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface))
                                              ])))),
                                ])))))));
  }
}

class _HeroStage extends StatefulWidget {
  const _HeroStage();
  @override
  State<_HeroStage> createState() => _HeroStageState();
}

class _HeroStageState extends State<_HeroStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = context.watch<SettingsViewModel>().settings.reduceMotion ||
        MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
    final theme = Theme.of(context);
    Widget line(double width) => Container(
        width: width,
        height: 5,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(6)));
    Widget card(String label, String title, String color, double width,
            {bool favorite = false, bool checklist = false}) =>
        Container(
            width: width,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.noteColor(theme.brightness, color),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF28281E).withValues(alpha: .14),
                      blurRadius: 30,
                      spreadRadius: -8,
                      offset: const Offset(0, 10))
                ]),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55))),
                  const SizedBox(height: 4),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3)),
                  if (checklist) ...[
                    const SizedBox(height: 10),
                    for (final item in [
                      ('Draft the user flow', true),
                      ('Review with Priya', false)
                    ])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(children: [
                            Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                    color: item.$2
                                        ? AppColors.primaryDark
                                        : Colors.transparent,
                                    border: Border.all(
                                        color: item.$2
                                            ? AppColors.primaryDark
                                            : theme.colorScheme.onSurface
                                                .withValues(alpha: .25),
                                        width: 1.5),
                                    borderRadius: BorderRadius.circular(4)),
                                child: item.$2
                                    ? const ReferenceIcon('check',
                                        size: 10, color: Colors.white)
                                    : null),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(item.$1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        decoration: item.$2
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: theme.colorScheme.onSurface
                                            .withValues(
                                                alpha: item.$2 ? .5 : 1))))
                          ]))
                  ] else ...[
                    line(width - 42),
                    line(width * .55)
                  ]
                ]));
    Widget badge(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .1),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 8))
            ]),
        child: child);
    return ExcludeSemantics(child: LayoutBuilder(builder: (context, size) {
      final scale =
          math.min(1.15, math.min(size.maxHeight / 300, size.maxWidth / 320));
      return Center(
          child: OverflowBox(
              maxWidth: 320,
              maxHeight: 300,
              child: Transform.scale(
                  scale: scale,
                  child: AnimatedBuilder(
                      animation: _motion,
                      builder: (context, child) => Transform.translate(
                          offset: Offset(
                              0,
                              reduced
                                  ? 0
                                  : math.sin(_motion.value * math.pi * 2) * 3),
                          child: child),
                      child: SizedBox(
                          width: 320,
                          height: 300,
                          child: Stack(clipBehavior: Clip.none, children: [
                            Positioned(
                                left: 25,
                                top: 15,
                                child: Container(
                                    width: 270,
                                    height: 270,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: .12)))),
                            Positioned(
                                left: 5,
                                top: -5,
                                child: Container(
                                    width: 310,
                                    height: 310,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: .25))))),
                            Positioned(
                                left: 0,
                                top: 12,
                                child: Transform.rotate(
                                    angle: -6 * math.pi / 180,
                                    child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          card(
                                              'AI',
                                              'Understanding Neural Networks',
                                              'lav',
                                              178),
                                          Positioned(
                                              right: -8,
                                              top: -8,
                                              child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                      color: theme
                                                          .colorScheme.surface,
                                                      shape: BoxShape.circle),
                                                  child: const Center(
                                                      child: ReferenceIcon(
                                                          'star',
                                                          size: 14,
                                                          color: AppColors.star,
                                                          filled: true))))
                                        ]))),
                            Positioned(
                                right: 0,
                                top: 48,
                                child: Transform.rotate(
                                    angle: 5 * math.pi / 180,
                                    child: card('Systems', 'OS — Scheduling',
                                        'mint', 160))),
                            Positioned(
                                left: 46,
                                top: 128,
                                child: Transform.rotate(
                                    angle: -2 * math.pi / 180,
                                    child: card('Projects',
                                        'Weekly Project Notes', 'yellow', 216,
                                        checklist: true))),
                            Positioned(
                                left: -4,
                                top: 104,
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                        color: theme.colorScheme.onSurface,
                                        borderRadius:
                                            BorderRadius.circular(30)),
                                    child: Row(children: [
                                      ReferenceIcon('spark',
                                          size: 13,
                                          color: theme.scaffoldBackgroundColor),
                                      const SizedBox(width: 6),
                                      Text('Summary ready',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: theme
                                                  .scaffoldBackgroundColor))
                                    ]))),
                            Positioned(
                                right: -6,
                                top: 230,
                                child: badge(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const NotedAvatar(
                                          name: 'Priya Raman',
                                          size: 24,
                                          color: Color(0xFFFFD5C8)),
                                      const NotedAvatar(
                                          name: 'Daniel Okoro',
                                          size: 24,
                                          color: Color(0xFFCFE6FF)),
                                      const SizedBox(width: 8),
                                      const Text('Editing live',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500)),
                                      const SizedBox(width: 8),
                                      Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.primary))
                                    ]))),
                          ]))))));
    }));
  }
}
