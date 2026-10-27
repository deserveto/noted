import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../repositories/profile_repository.dart';
import '../viewmodels/auth_viewmodel.dart';
import 'reference_icon.dart';

class LiveMetadata extends StatefulWidget {
  const LiveMetadata({super.key, required this.note});
  final NoteModel note;
  @override
  State<LiveMetadata> createState() => _LiveMetadataState();
}

class _LiveMetadataState extends State<LiveMetadata> {
  Future<List<UserModel?>>? _profiles;
  String _ids = '';
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthViewModel>().user?.uid;
    final ids = {widget.note.userId, ...widget.note.liveMemberIds}
        .where((id) => id != uid)
        .toList()
      ..sort();
    if (_ids != ids.join('|') || _profiles == null) {
      _ids = ids.join('|');
      _profiles = Future.wait(ids.map(ProfileRepository().load));
    }
    return FutureBuilder<List<UserModel?>>(
        future: _profiles,
        builder: (context, snapshot) {
          final names = (snapshot.data ?? [])
              .whereType<UserModel>()
              .map((p) => p.name.split(' ').first)
              .where((n) => n.isNotEmpty)
              .toList();
          final label = names.isEmpty
              ? 'Live'
              : 'Live with ${names.take(2).join(' & ')}${names.length > 2 ? ' +${names.length - 2}' : ''}';
          final color = Theme.of(context).colorScheme.primary;
          return Semantics(
              label: label,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ReferenceIcon('live', size: 13, color: color),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: color)))
              ]));
        });
  }
}
