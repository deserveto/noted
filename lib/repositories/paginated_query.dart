/// Reads every server page in a deterministic order supplied by the caller.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int start, int end) fetch, {
  int pageSize = 1000,
}) async {
  final rows = <T>[];
  for (var start = 0;; start += pageSize) {
    final page = await fetch(start, start + pageSize - 1);
    rows.addAll(page);
    if (page.length < pageSize) return rows;
  }
}
