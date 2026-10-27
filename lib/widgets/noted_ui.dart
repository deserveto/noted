import 'package:flutter/material.dart';
import '../services/media_url_resolver.dart';
import '../utils/app_colors.dart';
import 'reference_icon.dart';

String initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .take(2)
    .map((s) => s[0].toUpperCase())
    .join();
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
String relativeTime(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final minutes = today.difference(date).inMinutes;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '$minutes min ago';
  if (sameDay(date, today)) return '${today.difference(date).inHours} h ago';
  if (sameDay(date, today.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  if (today.difference(date).inDays < 6) return days[date.weekday - 1];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[date.month - 1]} ${date.day}';
}

class NotedBrand extends StatelessWidget {
  const NotedBrand({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('docs/Logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true),
        const SizedBox(width: 7),
        Text('noted',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 17, letterSpacing: -.3)),
      ]);
}

class NotedAvatar extends StatelessWidget {
  const NotedAvatar(
      {super.key,
      required this.name,
      this.uid = '',
      this.size = 36,
      this.photoUrl,
      this.color});
  final String name, uid;
  final double size;
  final String? photoUrl;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final hash = uid.codeUnits.fold<int>(0, (a, b) => a * 31 + b).abs();
    final fill = color ??
        (uid.isEmpty
            ? AppColors.secondary
            : AppColors.noteColors[[4, 0, 2, 5][hash % 4]]);
    final rawPhoto = photoUrl?.trim() ?? '';
    Widget avatarChild;
    if (rawPhoto.isEmpty) {
      avatarChild = _letters();
    } else {
      final immediate = MediaUrlResolver.peekResolved(
        rawPhoto,
        defaultBucket: MediaUrlResolver.avatarsBucket,
      );
      if (immediate != null) {
        avatarChild = Image.network(
          immediate,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => _letters(),
        );
      } else {
        avatarChild = FutureBuilder<String?>(
          future: MediaUrlResolver.resolve(
            rawPhoto,
            defaultBucket: MediaUrlResolver.avatarsBucket,
          ),
          builder: (context, snapshot) {
            final resolved = snapshot.data;
            if (resolved == null || resolved.isEmpty) return _letters();
            return Image.network(
              resolved,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => _letters(),
            );
          },
        );
      }
    }
    return Semantics(
        label: name,
        image: true,
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
            clipBehavior: Clip.antiAlias,
            child: avatarChild));
  }

  Widget _letters() => Center(
      child: Text(initials(name).isEmpty ? '?' : initials(name),
          style: TextStyle(
              fontSize: size * .36,
              fontWeight: FontWeight.w600,
              color: AppColors.text)));
}

class PageHeading extends StatelessWidget {
  const PageHeading(
      {super.key, required this.title, this.accent, this.metadata});
  final String title;
  final String? accent, metadata;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (metadata != null) ...[
          Text(metadata!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 13)),
          const SizedBox(height: 4)
        ],
        Text.rich(
            TextSpan(text: title, children: [
              if (accent != null)
                TextSpan(
                    text: accent,
                    style: const TextStyle(
                        fontFamily: 'Newsreader',
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400))
            ]),
            style: Theme.of(context).textTheme.headlineMedium),
      ]);
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontSize: 18, letterSpacing: -.2))),
        if (action != null)
          TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(fontSize: 13))),
      ]));
}

class SurfacePanel extends StatelessWidget {
  const SurfacePanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor)),
      child: child);
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.label = 'Live'});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        ReferenceIcon('live',
            size: 13, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.primary))
      ]);
}

class ActivityDots extends StatelessWidget {
  const ActivityDots(this.count,
      {super.key, this.selected = false, this.visible = true});
  final int count;
  final bool selected, visible;
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 6,
      child: ExcludeSemantics(
          child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            if (visible)
              for (var i = 0; i < count.clamp(0, 3); i++)
                Container(
                    width: 5,
                    height: 5,
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? AppColors.secondary
                            : Theme.of(context).colorScheme.primary)),
          ])));
}

class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
                child: Text(message,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13))),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry'))
          ])));
}

Future<T?> notedSheet<T>(BuildContext context,
        {required String label,
        required WidgetBuilder builder,
        bool tall = false}) =>
    showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        barrierLabel: 'Close $label',
        constraints: const BoxConstraints(maxWidth: 600),
        builder: (context) => Semantics(
            namesRoute: true,
            label: label,
            child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: tall
                    ? SizedBox(
                        height: MediaQuery.sizeOf(context).height * .85,
                        child: builder(context))
                    : builder(context))));

void notedToast(BuildContext context, String text, {VoidCallback? undo}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
      content: Text(text),
      duration: Duration(milliseconds: undo == null ? 2400 : 4500),
      action: undo == null
          ? null
          : SnackBarAction(label: 'Undo', onPressed: undo)));
}

class _SkeletonShapes extends StatelessWidget {
  const _SkeletonShapes();
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Loading notes',
      liveRegion: true,
      child: Column(children: [
        for (var row = 0; row < 2; row++)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                for (var col = 0; col < 2; col++)
                  Expanded(
                      child: Container(
                          height: 180,
                          margin: EdgeInsets.only(
                              left: col == 1 ? 6 : 0, right: col == 0 ? 6 : 0),
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0; i < 4; i++)
                                  Container(
                                      height: i == 1 ? 18 : 8,
                                      width: i == 3 ? 60 : double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      color: Theme.of(context).dividerColor)
                              ])))
              ]))
      ]));
}

class NoteSkeleton extends StatefulWidget {
  const NoteSkeleton({super.key});
  @override
  State<NoteSkeleton> createState() => _NoteSkeletonState();
}

class _NoteSkeletonState extends State<NoteSkeleton>
    with SingleTickerProviderStateMixin {
  late final _opacity = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: .55,
      upperBound: 1,
      value: 1);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _opacity.stop();
      _opacity.value = 1;
    } else if (!_opacity.isAnimating) {
      _opacity.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: const _SkeletonShapes());
}
