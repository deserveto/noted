import 'package:flutter_test/flutter_test.dart';
import 'package:noted/utils/note_links.dart';

void main() {
  test('member links round trip through native route parsing', () {
    expect(noteInviteLink('abc-123'), 'noted://app/notes/abc-123');
    expect(noteIdFromLink(noteInviteLink('abc-123')), 'abc-123');
    expect(noteIdFromLink('/notes/abc-123'), 'abc-123');
  });
  test('unrelated or malformed routes do not become note IDs', () {
    for (final value in [
      'https://evil/notes/abc',
      'noted://wrong/notes/abc',
      '/notes/a/b',
      '/notes/a%2Fb',
      '/notes/new',
      '/notes/'
    ]) {
      expect(noteIdFromLink(value), isNull, reason: value);
    }
  });
}
