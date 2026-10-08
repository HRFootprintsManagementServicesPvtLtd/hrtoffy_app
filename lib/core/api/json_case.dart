// Helpers that let repositories hand the UI the same snake_case, plain-typed
// maps it used to receive from Supabase, regardless of how the HR Toffy
// backend serialises them (camelCase DTOs, Decimal strings, ISO datetimes).

String _camelToSnake(String key) {
  if (key.isEmpty) return key;
  final out = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final c = key[i];
    final isUpper = c.toLowerCase() != c && c.toUpperCase() == c;
    if (isUpper && i > 0 && key[i - 1] != '_') out.write('_');
    out.write(c.toLowerCase());
  }
  return out.toString();
}

/// Recursively converts every Map key to snake_case. Lists are mapped,
/// values are left untouched. Keys that are already snake_case are unchanged.
dynamic snakeKeys(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) _camelToSnake(e.key.toString()): snakeKeys(e.value),
    };
  }
  if (value is List) return value.map(snakeKeys).toList();
  return value;
}

String _snakeToCamel(String key) {
  if (!key.contains('_')) return key;
  final parts = key.split('_').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return key;
  return parts.first + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

/// Converts the TOP-LEVEL keys of a request body from the UI's snake_case to the
/// camelCase the backend expects. Values are untouched.
Map<String, dynamic> camelKeys(Map<String, dynamic> map) => {
      for (final e in map.entries) _snakeToCamel(e.key): e.value,
    };

/// Reads `data` as a list whether the backend returned a bare list,
/// `{items: [...]}` or `{data: [...]}`.
List<Map<String, dynamic>> asMapList(dynamic data) {
  dynamic list = data;
  if (list is Map) list = list['items'] ?? list['data'] ?? const [];
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

/// Decimal columns arrive as strings ("2.50"); returns a num either way.
num? asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

double asDouble(dynamic v, [double fallback = 0]) => asNum(v)?.toDouble() ?? fallback;

int asInt(dynamic v, [int fallback = 0]) => asNum(v)?.toInt() ?? fallback;

/// Parses ISO strings such as `2026-10-07T00:00:00.000Z` or `2026-10-07`.
DateTime? asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

/// `yyyy-MM-dd` for a date value (drops any time part so date-only columns
/// compare equal to the strings the UI builds).
String? asDateOnly(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return s.length >= 10 ? s.substring(0, 10) : s;
}
