/// Member-only links handled by Noted's native Android route handler.
String noteInviteLink(String noteId) =>
    Uri(scheme: 'noted', host: 'app', pathSegments: ['notes', noteId])
        .toString();
String? noteIdFromLink(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.hasScheme && (uri.scheme != 'noted' || uri.host != 'app'))) {
    return null;
  }
  final parts = uri.pathSegments;
  if (parts.length != 2 || parts.first != 'notes' || parts.last == 'new') {
    return null;
  }
  final id = parts.last;
  return id.isNotEmpty && id.length <= 128 && !RegExp(r'[/\s]').hasMatch(id)
      ? id
      : null;
}
