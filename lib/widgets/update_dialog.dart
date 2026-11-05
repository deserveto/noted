import 'package:flutter/material.dart';
import '../models/app_release.dart';
import '../viewmodels/update_viewmodel.dart';

class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.release});
  final AppRelease release;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${release.version} · build ${release.build} · Beta',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${release.sizeLabel} download',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          for (final change in release.changes)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    '${change.type[0].toUpperCase()}${change.type.substring(1)}: ${change.text}')),
        ],
      );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog(
      {super.key,
      required this.vm,
      required this.release,
      this.whatsNew = false});
  final UpdateViewModel vm;
  final AppRelease release;
  final bool whatsNew;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: vm,
        builder: (context, _) => AlertDialog(
          title: Text(whatsNew ? 'What’s new' : 'A new beta is ready'),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReleaseNotes(release: release),
                      if (!whatsNew) ...[
                        const Text(
                            'The APK opens in your browser. After downloading, open it and finish installation in Android. Your notes stay in Noted.'),
                        if (vm.downloadError != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Text(vm.downloadError!))),
                      ],
                    ]),
              )),
          actions: [
            TextButton(
                onPressed: vm.downloading ? null : () => Navigator.pop(context),
                child: Text(whatsNew ? 'Done' : 'Later')),
            if (!whatsNew)
              FilledButton(
                  onPressed: vm.downloading
                      ? null
                      : () async {
                          if (await vm.download(release) && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  child: Text(vm.downloading ? 'Opening…' : 'Update now')),
          ],
        ),
      );
}

Future<void> showUpdateDialog(
    BuildContext context, UpdateViewModel vm, AppRelease release,
    {bool whatsNew = false}) async {
  await showDialog<void>(
      context: context,
      builder: (_) =>
          UpdateDialog(vm: vm, release: release, whatsNew: whatsNew));
  if (whatsNew) {
    await vm.markWhatsNewShown();
  } else {
    await vm.remindLater();
  }
}
