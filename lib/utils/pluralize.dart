String pluralize(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

String pluralNoun(int count, String singular, [String? plural]) =>
    count == 1 ? singular : (plural ?? '${singular}s');
