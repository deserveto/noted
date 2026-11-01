import 'package:flutter_test/flutter_test.dart';
import 'package:noted/utils/pluralize.dart';

void main() {
  group('pluralize', () {
    test('formats singular count correctly', () {
      expect(pluralize(1, 'note'), '1 note');
      expect(pluralize(1, 'favorite'), '1 favorite');
      expect(pluralize(1, 'active day'), '1 active day');
      expect(pluralize(1, 'match', 'matches'), '1 match');
    });

    test('formats zero and plural counts correctly', () {
      expect(pluralize(0, 'note'), '0 notes');
      expect(pluralize(2, 'note'), '2 notes');
      expect(pluralize(0, 'favorite'), '0 favorites');
      expect(pluralize(5, 'favorite'), '5 favorites');
      expect(pluralize(2, 'active day'), '2 active days');
      expect(pluralize(0, 'match', 'matches'), '0 matches');
      expect(pluralize(3, 'match', 'matches'), '3 matches');
    });

    test('pluralNoun returns only noun', () {
      expect(pluralNoun(1, 'note'), 'note');
      expect(pluralNoun(0, 'note'), 'notes');
      expect(pluralNoun(2, 'note'), 'notes');
      expect(pluralNoun(1, 'match', 'matches'), 'match');
      expect(pluralNoun(4, 'match', 'matches'), 'matches');
    });
  });
}
