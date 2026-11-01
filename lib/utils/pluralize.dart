/// Formats a count and noun with correct singular/plural English grammar.
///
/// When [count] is 1, uses [singular].
/// Otherwise, uses [plural] if provided, or appends 's' to [singular].
/// Returns '$count $noun'.
String pluralize(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

/// Returns just the noun in singular or plural form based on [count].
String pluralNoun(int count, String singular, [String? plural]) =>
    count == 1 ? singular : (plural ?? '${singular}s');
