import '../core/api/json_case.dart';
import 'base_repository.dart';

/// The compliance screens' reads. Every method is a GET.
///
/// The server grants compliance.view to HR managers and above only; a plain manager gets 403 on every one of these
/// routes (the screen turns that into one friendly message). Rows are raw snake_case rows.
class ComplianceRepository extends BaseRepository {
  ComplianceRepository({super.auth});

  /// `GET /organizations/:orgId/compliance/health` -> the latest snapshot (`overall_score`, `snapshot_date`), or
  /// `overall_score: null` when no snapshot exists yet. Returns the score as an int, or null when unknown (never 0).
  Future<int?> healthScore() async {
    final data = await api.get(orgPath('/compliance/health'));
    if (data is! Map) return null;
    final n = asNum(data['overall_score']);
    return n?.round();
  }

  /// `GET /organizations/:orgId/compliance/wage-register/<kind>` with kind `fines`, `deductions` or `advances` (a plain
  /// list, newest first). Employees come as ids only (`employee_id`); see [employeeNames].
  Future<List<Map<String, dynamic>>> wageRegister(String kind) async {
    assert(kind == 'fines' || kind == 'deductions' || kind == 'advances');
    final data = await api.get(orgPath('/compliance/wage-register/$kind'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/compliance/returns?limit=200` -> `{items,...}` (`return_type`, `period_month`,
  /// `period_year`, `period_label`, `due_date`, `status`, `challan_amount`), latest due date first.
  Future<List<Map<String, dynamic>>> returns() async {
    final data = await api.get(
      orgPath('/compliance/returns'),
      query: {'limit': 200},
    );
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/compliance/factory-accidents` (plain list: `injury_type`, `accident_location`, `status`,
  /// `accident_datetime`).
  Future<List<Map<String, dynamic>>> factoryAccidents() async {
    final data = await api.get(orgPath('/compliance/factory-accidents'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/compliance/shops-certs` (plain list: `establishment_name`, `certificate_number`,
  /// `valid_until`, `status`).
  Future<List<Map<String, dynamic>>> shopsCerts() async {
    final data = await api.get(orgPath('/compliance/shops-certs'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/bonus-runs` (plain list; needs payroll.view, HR managers and above: `accounting_year`,
  /// `status`, `total_eligible_employees`, `total_payout_amount`, `bonus_pct_applied`).
  Future<List<Map<String, dynamic>>> bonusRuns() async {
    final data = await api.get(orgPath('/bonus-runs'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/gratuity/provisions` (plain list: `employee_id`, `eligible_service_years`,
  /// `provision_amount`, `period_month`).
  Future<List<Map<String, dynamic>>> gratuityProvisions() async {
    final data = await api.get(orgPath('/gratuity/provisions'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/posh/complaints?limit=200` -> `{items,...}` (`case_number`, `status`).
  Future<List<Map<String, dynamic>>> poshComplaints() async {
    final data = await api.get(
      orgPath('/posh/complaints'),
      query: {'limit': 200},
    );
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/maternity/cases` (plain list: `employee_name`, `leave_type`, `expected_delivery_date`).
  Future<List<Map<String, dynamic>>> maternityCases() async {
    final data = await api.get(orgPath('/maternity/cases'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/locum/contractors?limit=200` -> `{items,...}` (CLRA contractors: `name`,
  /// `license_number`, `license_expiry`).
  Future<List<Map<String, dynamic>>> contractors() async {
    final data = await api.get(
      orgPath('/locum/contractors'),
      query: {'limit': 200},
    );
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/compliance/apprentices` (plain list: `apprentice_name`, `trade`, `status`).
  Future<List<Map<String, dynamic>>> apprentices() async {
    final data = await api.get(orgPath('/compliance/apprentices'));
    return asMapList(data);
  }

  /// Employee id -> full name, one call: `GET /organizations/:orgId/employees/summaries` (any member may call it; it
  /// answers camelCase `{id, employeeId, fullName, email}`). The compliance registers carry employee ids only. Callers
  /// treat a failure as "names unknown" and show "Employee", never a guess.
  Future<Map<String, String>> employeeNames() async {
    final data = await api.get(orgPath('/employees/summaries'));
    final out = <String, String>{};
    for (final raw in asMapList(data)) {
      final e = snakeKeys(raw) as Map;
      final id = e['id']?.toString();
      final name = e['full_name']?.toString();
      if (id != null && name != null && name.isNotEmpty) out[id] = name;
    }
    return out;
  }
}
