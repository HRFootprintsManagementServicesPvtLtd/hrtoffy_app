import '../core/api/json_case.dart';
import 'base_repository.dart';

/// One page of requisitions: `{items, page, limit, total}`.
class RequisitionPage {
  const RequisitionPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<Map<String, dynamic>> items;
  final int page;
  final int limit;
  final int total;
}

/// Job requisitions for a manager: their own plus their reporting tree's (the server scopes the list).
/// Create / edit / submit / cancel are for the requester only. Deciding (`POST /:id/decide`) is HR/approver-only and is
/// deliberately not part of this class.
class RequisitionsRepository extends BaseRepository {
  RequisitionsRepository({super.auth});

  /// The only keys the server accepts in a create/patch body (unknown keys are refused with 400).
  static const Set<String> bodyKeys = {
    'position_title',
    'department',
    'location',
    'reporting_to',
    'employment_type',
    'number_of_positions',
    'priority',
    'is_replacement',
    'replacing_employee_id',
    'experience_min',
    'experience_max',
    'salary_min',
    'salary_max',
    'currency',
    'key_skills',
    'qualifications',
    'job_description',
    'business_justification',
    'expected_joining_date',
  };

  String get _base => orgPath('/recruitment/requisitions');

  /// Whether [requestedBy] is the signed-in user (the id may be the employee id or the user id).
  bool isMine(dynamic requestedBy) {
    final v = requestedBy?.toString();
    if (v == null || v.isEmpty) return false;
    final u = auth.currentUser;
    return v == u?.employeeId || v == u?.id;
  }

  /// `GET .../requisitions?status=&page=&limit=` (newest first). [status] null reads every status.
  Future<RequisitionPage> list({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await api.get(
      _base,
      query: {
        'page': '$page',
        'limit': '${limit.clamp(1, 100)}',
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final items = asMapList(data).map(_snake).toList();
    if (data is Map) {
      return RequisitionPage(
        items: items,
        page: asInt(data['page'], page),
        limit: asInt(data['limit'], limit),
        total: asInt(data['total'], items.length),
      );
    }
    return RequisitionPage(
      items: items,
      page: page,
      limit: limit,
      total: items.length,
    );
  }

  /// `GET .../requisitions/:id`.
  Future<Map<String, dynamic>> byId(String id) async {
    final data = await api.get('$_base/$id');
    return data is Map ? _snake(data) : <String, dynamic>{};
  }

  /// `POST .../requisitions` (201). [submit] true creates it as `pending_approval`, otherwise as a draft.
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> fields, {
    bool submit = false,
  }) async {
    final data = await api.post(
      _base,
      body: {..._clean(fields), 'submit': submit},
    );
    return data is Map ? _snake(data) : <String, dynamic>{};
  }

  /// `PATCH .../requisitions/:id` with any subset of the fields (requester only; draft or rejected).
  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final data = await api.patch('$_base/$id', body: _clean(fields));
    return data is Map ? _snake(data) : <String, dynamic>{};
  }

  /// `POST .../requisitions/:id/submit` (no body).
  Future<Map<String, dynamic>> submit(String id) async {
    final data = await api.post('$_base/$id/submit');
    return data is Map ? _snake(data) : <String, dynamic>{};
  }

  /// `POST .../requisitions/:id/cancel` (no body).
  Future<Map<String, dynamic>> cancel(String id) async {
    final data = await api.post('$_base/$id/cancel');
    return data is Map ? _snake(data) : <String, dynamic>{};
  }

  /// Employee id -> full name (`GET .../employees/summaries`), for the "reports to" picker.
  Future<Map<String, String>> employeeNames() async {
    final data = await api.get(orgPath('/employees/summaries'));
    final out = <String, String>{};
    for (final raw in asMapList(data)) {
      final e = _snake(raw);
      final id = e['id']?.toString();
      final name = e['full_name']?.toString();
      if (id != null && name != null && name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  static Map<String, dynamic> _clean(Map<String, dynamic> f) => {
    for (final e in f.entries)
      if (bodyKeys.contains(e.key)) e.key: e.value,
  };

  static Map<String, dynamic> _snake(Map m) =>
      Map<String, dynamic>.from(snakeKeys(m) as Map);
}
