import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/media_url_resolver.dart';
import 'reference_icon.dart';

class NoteAttachment extends StatefulWidget {
  const NoteAttachment({required this.attachment, this.onRemove, super.key});
  final Map<String, dynamic> attachment;
  final VoidCallback? onRemove;
  @override
  State<NoteAttachment> createState() => _NoteAttachmentState();
}

class _NoteAttachmentState extends State<NoteAttachment> {
  final _player = AudioPlayer();
  bool _playing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Widget _buildNetworkImage(String resolvedUrl) => Image.network(
        resolvedUrl,
        width: double.infinity,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Padding(
                padding: EdgeInsets.all(24),
                child: LinearProgressIndicator()),
        errorBuilder: (context, error, stack) => const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
                'Image unavailable. Check your connection and reopen the note.')),
      );

  Widget _buildImageAttachment(String rawUrl, String? rawPath) {
    final immediate = MediaUrlResolver.peekResolved(
      rawUrl,
      fallbackPath: rawPath,
    );
    if (immediate != null) {
      return _buildNetworkImage(immediate);
    }
    return FutureBuilder<String?>(
      future: MediaUrlResolver.resolve(rawUrl, fallbackPath: rawPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: LinearProgressIndicator(),
          );
        }
        final resolved = snapshot.data;
        if (resolved == null || resolved.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
                'Image unavailable. Check your connection and reopen the note.'),
          );
        }
        return _buildNetworkImage(resolved);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    final audio = a['type'] == 'audio';
    final seconds = (a['duration'] as num?)?.toInt() ?? 0;
    final rawUrl = (a['url'] as String?) ?? '';
    final rawPath = a['path'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (audio)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              IconButton(
                  tooltip: _playing ? 'Pause voice memo' : 'Play voice memo',
                  onPressed: () async {
                    try {
                      if (_playing) {
                        await _player.pause();
                      } else {
                        final resolved = await MediaUrlResolver.resolve(
                          rawUrl,
                          fallbackPath: rawPath,
                        );
                        if (resolved == null || resolved.isEmpty) {
                          throw StateError('Audio unavailable');
                        }
                        await _player.play(UrlSource(resolved));
                      }
                      if (mounted) {
                        setState(() {
                          _playing = !_playing;
                          _error = null;
                        });
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() =>
                            _error = 'Unable to play audio. Tap to retry.');
                      }
                    }
                  },
                  icon: ReferenceIcon(_playing ? 'pause' : 'play')),
              const ReferenceIcon('mic', size: 18),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'Voice memo · ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}')),
              if (widget.onRemove != null)
                IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: widget.onRemove,
                    icon: const ReferenceIcon('x', size: 16)),
            ]),
          )
        else
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _buildImageAttachment(rawUrl, rawPath),
            ),
            if (widget.onRemove != null)
              Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(
                      tooltip: 'Remove attachment',
                      onPressed: widget.onRemove,
                      icon: const ReferenceIcon('x', size: 16))),
          ]),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    );
  }
}

class RecordedAudio {
  const RecordedAudio(this.bytes, this.seconds);
  final Uint8List bytes;
  final int seconds;
}

class AudioRecordingSheet extends StatefulWidget {
  const AudioRecordingSheet({super.key});
  @override
  State<AudioRecordingSheet> createState() => _AudioRecordingSheetState();
}

class _AudioRecordingSheetState extends State<AudioRecordingSheet> {
  final _recorder = AudioRecorder();
  final _watch = Stopwatch();
  Timer? _timer;
  bool _recording = false;
  bool _stopping = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError(
            'Allow microphone access in device settings to record a voice memo.');
      }
      final directory = await getTemporaryDirectory();
      await _recorder.start(const RecordConfig(),
          path:
              '${directory.path}/noted_${DateTime.now().microsecondsSinceEpoch}.m4a');
      _watch.start();
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    try {
      final path = await _recorder.stop();
      _watch.stop();
      if (path == null) {
        throw StateError('Recording could not be saved. Please try again.');
      }
      final bytes = await XFile(path).readAsBytes();
      if (mounted) {
        Navigator.pop(context, RecordedAudio(bytes, _watch.elapsed.inSeconds));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _stopping = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sec = _watch.elapsed.inSeconds;
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_recording ? 'Recording' : 'Record audio',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text('${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 40,
                      fontFeatures: [ui.FontFeature.tabularFigures()])),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: _stopping
                            ? null
                            : () async {
                                await _recorder.cancel();
                                if (context.mounted) Navigator.pop(context);
                              },
                        child: const Text('Discard'))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                        onPressed: _recording && !_stopping ? _stop : null,
                        child: Text(_stopping ? 'Adding…' : 'Stop & add'))),
              ]),
            ])));
  }
}

class DoodleSheet extends StatefulWidget {
  const DoodleSheet({super.key});
  @override
  State<DoodleSheet> createState() => _DoodleSheetState();
}

class _Stroke {
  _Stroke(this.color, this.points);
  final Color color;
  final List<Offset> points;
}

class _DoodleSheetState extends State<DoodleSheet> {
  final _key = GlobalKey();
  final _strokes = <_Stroke>[];
  Color _ink = const Color(0xff2f2f2f);
  bool _busy = false;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(
                  child: Text('Doodle',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(
                  tooltip: 'Close doodle',
                  onPressed: () => Navigator.pop(context),
                  icon: const ReferenceIcon('x'))
            ]),
            RepaintBoundary(
                key: _key,
                child: GestureDetector(
                  onPanStart: (e) => setState(
                      () => _strokes.add(_Stroke(_ink, [e.localPosition]))),
                  onPanUpdate: (e) =>
                      setState(() => _strokes.last.points.add(e.localPosition)),
                  child: AspectRatio(
                      aspectRatio: 700 / 480,
                      child: CustomPaint(
                          painter: _DoodlePainter(_strokes),
                          child: const SizedBox.expand())),
                )),
            const SizedBox(height: 12),
            Row(children: [
              for (final c in const [
                Color(0xff2f2f2f),
                Color(0xff4f7e6c),
                Color(0xffe57373),
                Color(0xff5b8def)
              ])
                Semantics(
                    selected: _ink == c,
                    child: IconButton(
                        tooltip: 'Ink ${c.toARGB32().toRadixString(16)}',
                        onPressed: () => setState(() => _ink = c),
                        icon: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: _ink == c
                                    ? Border.all(color: Colors.white, width: 3)
                                    : null)))),
              const Spacer(),
              TextButton(
                  onPressed: () => setState(_strokes.clear),
                  child: const Text('Clear')),
              FilledButton(
                  onPressed: _strokes.isEmpty || _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final image = await (_key.currentContext!
                                  .findRenderObject()! as RenderRepaintBoundary)
                              .toImage(pixelRatio: 2);
                          final data = await image.toByteData(
                              format: ui.ImageByteFormat.png);
                          image.dispose();
                          if (context.mounted) {
                            Navigator.pop(context, data!.buffer.asUint8List());
                          }
                        },
                  child: Text(_busy ? 'Adding…' : 'Add')),
            ]),
          ])));
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.strokes);
  final List<_Stroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
        Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final stroke in strokes) {
      final p = Paint()
        ..color = stroke.color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, 1.25, p);
      }
      for (var i = 1; i < stroke.points.length; i++) {
        canvas.drawLine(stroke.points[i - 1], stroke.points[i], p);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter oldDelegate) => true;
}
