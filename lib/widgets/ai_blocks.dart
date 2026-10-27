import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'reference_icon.dart';

class AiBlocks extends StatelessWidget {
  const AiBlocks({super.key, required this.blocks});
  final List<dynamic> blocks;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final b in blocks.whereType<Map>())
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: switch (b['t']) {
                'h' => Text('${b['x']}'.toUpperCase(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .6)),
                'quote' => Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2))),
                    child: Text('${b['x']}',
                        style: TextStyle(
                            fontFamily: 'Newsreader',
                            fontStyle: FontStyle.italic,
                            fontSize: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant))),
                'cards' => Flashcards(
                    cards: (b['cards'] as List? ?? [])
                        .whereType<Map>()
                        .map((v) => Map<String, dynamic>.from(v))
                        .toList()),
                'ul' || 'ol' || 'todo' => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, item)
                            in (b['items'] as List? ?? []).indexed)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (b['t'] == 'todo')
                                      const Padding(
                                          padding:
                                              EdgeInsets.only(top: 3, right: 8),
                                          child:
                                              ReferenceIcon('todo', size: 18))
                                    else
                                      SizedBox(
                                          width: 22,
                                          child: Text(
                                              b['t'] == 'ol' ? '${i + 1}' : '•',
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.65))),
                                    Expanded(
                                        child: Text('$item',
                                            style: const TextStyle(
                                                fontSize: 15, height: 1.65)))
                                  ]))
                      ]),
                _ => Text('${b['x'] ?? ''}',
                    style: const TextStyle(fontSize: 15, height: 1.65)),
              })
      ]);
}

class Flashcards extends StatefulWidget {
  const Flashcards({super.key, required this.cards});
  final List<Map<String, dynamic>> cards;
  @override
  State<Flashcards> createState() => _FlashcardsState();
}

class _FlashcardsState extends State<Flashcards> {
  int _index = 0;
  bool _answer = false;
  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    final card = widget.cards[_index.clamp(0, widget.cards.length - 1)];
    return Column(children: [
      Semantics(
          button: true,
          label: _answer
              ? 'Answer: ${card['a']}. Tap to see question'
              : 'Question: ${card['q']}. Tap to reveal answer',
          child: InkWell(
              onTap: () => setState(() => _answer = !_answer),
              borderRadius: BorderRadius.circular(16),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                    begin: 0, end: _answer ? 3.141592653589793 : 0),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                builder: (context, angle, child) {
                  final back = angle > 1.5707963267948966;
                  return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .001)
                        ..rotateY(angle),
                      child: Transform(
                          alignment: Alignment.center,
                          transform:
                              Matrix4.rotationY(back ? 3.141592653589793 : 0),
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 144),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: AppColors.noteColorFor(
                                    Theme.of(context).brightness, back ? 2 : 5),
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(back ? 'ANSWER' : 'QUESTION',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              fontSize: 11, letterSpacing: .8)),
                                  const SizedBox(height: 12),
                                  Text('${card[back ? 'a' : 'q']}',
                                      style: TextStyle(
                                          fontSize: back ? 15 : 16,
                                          fontWeight: back
                                              ? FontWeight.w400
                                              : FontWeight.w600,
                                          height: 1.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                      back
                                          ? 'Tap to flip back'
                                          : 'Tap to reveal',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ]),
                          )));
                },
              ))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(
            tooltip: 'Previous card',
            onPressed: _index == 0
                ? null
                : () => setState(() {
                      _index--;
                      _answer = false;
                    }),
            icon: const ReferenceIcon('back', size: 18)),
        Text('${_index + 1} / ${widget.cards.length}',
            style: Theme.of(context).textTheme.bodySmall),
        IconButton(
            tooltip: 'Next card',
            onPressed: _index >= widget.cards.length - 1
                ? null
                : () => setState(() {
                      _index++;
                      _answer = false;
                    }),
            icon: const ReferenceIcon('next', size: 18))
      ])
    ]);
  }
}
