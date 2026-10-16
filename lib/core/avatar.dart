/// The profile photo address from an employee record, or null when there is no usable photo.
///
/// A removed photo can come back from the server as an empty string (or whitespace) instead of null; an empty address must be
/// treated as "no photo" everywhere, otherwise the avatar is drawn as an empty / broken image instead of the user's initial.
String? cleanAvatarUrl(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final lower = s.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) return null;
  return s;
}
