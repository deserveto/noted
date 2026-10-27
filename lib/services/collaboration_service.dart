import '../repositories/note_repository.dart';
import 'supabase_service.dart';

class CollaborationService {
  Future<String> duplicate({
    required String noteId,
    required Map<String, dynamic> draft,
  }) async {
    final hasExplicitTitle =
        draft['title'] != null && draft['title'].toString().trim().isNotEmpty;
    final result = await SupabaseService.invokeFunction(
      'note-sharing',
      {
        'action': 'duplicateNote',
        'noteId': noteId,
        'draft': draft,
        if (hasExplicitTitle) 'preserveExactTitle': true,
      },
    );
    return result['noteId'] as String;
  }

  Future<void> setLiveRole({
    required String noteId,
    required String targetUserId,
    String? role,
  }) =>
      NoteRepository().setLiveRole(noteId, targetUserId, role);
}
