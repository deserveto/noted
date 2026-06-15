import 'package:flutter_test/flutter_test.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/utils/markdown_formatter.dart';

void main() {
  test('note model preserves sharing metadata', () {
    final now = DateTime(2026, 6, 14);
    final note = NoteModel(
      noteId: 'note-1',
      userId: 'owner-1',
      ownerName: 'Diaz',
      ownerEmail: 'diaz@example.com',
      title: 'Data Structures',
      content: '**Stack** notes',
      category: 'Lecture notes',
      isFavorite: false,
      sharedWithUserIds: const ['friend-1'],
      pendingSharedWithUserIds: const [],
      createdAt: now,
      updatedAt: now,
    );

    final roundTrip = NoteModel.fromMap(note.toMap());

    expect(roundTrip.ownerName, 'Diaz');
    expect(roundTrip.ownerEmail, 'diaz@example.com');
    expect(roundTrip.sharedWithUserIds, ['friend-1']);
    expect(roundTrip.isSharedWith('friend-1'), isTrue);
    expect(roundTrip.isOwner('owner-1'), isTrue);
  });

  test('accepted connection resolves the other user for current user', () {
    final connection = ConnectionModel(
      connectionId: 'connection-1',
      fromUserId: 'user-a',
      fromName: 'Alya',
      fromEmail: 'alya@example.com',
      toUserId: 'user-b',
      toName: 'Bima',
      toEmail: 'bima@example.com',
      status: ConnectionStatus.accepted,
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14),
    );

    expect(connection.otherUserId('user-a'), 'user-b');
    expect(connection.otherName('user-a'), 'Bima');
    expect(connection.otherEmail('user-b'), 'alya@example.com');
    expect(connection.involves('user-a'), isTrue);
  });

  test('markdown formatter applies inline and list markup to selection', () {
    expect(
      MarkdownFormatter.apply('hello', 0, 5, MarkdownFormat.bold).text,
      '**hello**',
    );
    expect(
      MarkdownFormatter.apply('read notes', 0, 10, MarkdownFormat.bullet).text,
      '- read notes',
    );
    expect(
      MarkdownFormatter.apply('read notes', 0, 10, MarkdownFormat.numbered)
          .text,
      '1. read notes',
    );
  });

  test('markdown formatter toggles inline markup around selections', () {
    final bold = MarkdownFormatter.apply(
      'hello',
      0,
      5,
      MarkdownFormat.bold,
    );

    expect(
      MarkdownFormatter.apply(
        bold.text,
        0,
        bold.text.length,
        MarkdownFormat.bold,
      ).text,
      'hello',
    );
  });

  test('markdown formatter creates inline typing zones', () {
    final edit = MarkdownFormatter.activateInlineTypingZone(
      'Study ',
      6,
      MarkdownFormat.bold,
    );

    expect(edit.text, 'Study ****');
    expect(edit.selection.baseOffset, 8);
  });

  test('markdown formatter continues bullet and numbered lists', () {
    expect(
      MarkdownFormatter.continueListAfterNewline('- first\n', 8, true),
      '- first\n- ',
    );
    expect(
      MarkdownFormatter.continueListAfterNewline('1. first\n', 9, false),
      '1. first\n2. ',
    );
  });

  test('markdown formatter removes markup for previews', () {
    expect(
      MarkdownFormatter.toPlainText('**Bold** _italic_ <u>underlined</u>'),
      'Bold italic underlined',
    );
  });

  test('markdown formatter toggles inline typing spans at the cursor', () {
    final activated = MarkdownFormatter.activateInlineTyping(
      'Hello ',
      6,
      MarkdownFormat.bold,
    );

    expect(activated.text, 'Hello ****');
    expect(activated.selection.baseOffset, 8);

    final deactivated = MarkdownFormatter.deactivateInlineTyping(
      activated.text,
      activated.selection.baseOffset,
      MarkdownFormat.bold,
    );

    expect(deactivated.text, 'Hello ****');
    expect(deactivated.selection.baseOffset, 10);
  });

  test('markdown formatter continues active list markers after a newline', () {
    final bullet = MarkdownFormatter.continueListAfterNewline(
      '- Read\n',
      7,
      MarkdownFormat.bullet,
    );

    expect(bullet.text, '- Read\n- ');
    expect(bullet.selection.baseOffset, 9);

    final numbered = MarkdownFormatter.continueListAfterNewline(
      '1. Read\n',
      8,
      MarkdownFormat.numbered,
    );

    expect(numbered.text, '1. Read\n2. ');
    expect(numbered.selection.baseOffset, 11);
  });
}
