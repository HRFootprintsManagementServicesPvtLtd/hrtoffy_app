// Single source of truth for the "leave summary" numbers shown on the
// Dashboard leave-balance card and on the Leave screen summary cards.
//
// It wraps the get_my_leave_summary() SECURITY DEFINER RPC (added to
// bypass the RLS chain that was causing 57014 timeouts) and normalises
// the response into a shape both screens can consume without duplicating
// business logic.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaveSummaryPolicy {
  final String name;
  final int allocated;
  final int used;
  final int remaining;
  const LeaveSummaryPolicy({
    required this.name,
    required this.allocated,
    required this.used,
    required this.remaining,
  });
}

class LeaveSummary {
  final int totalAllocated;
  final int totalUsed;
  final int totalRemaining;
  final int pendingRequests;
  final int leavePolicyCount;
  final int year;
  final List<LeaveSummaryPolicy> policies;

  const LeaveSummary({
    required this.totalAllocated,
    required this.totalUsed,
    required this.totalRemaining,
    required this.pendingRequests,
    required this.leavePolicyCount,
    required this.year,
    required this.policies,
  });

  factory LeaveSummary.empty([int? year]) => LeaveSummary(
    totalAllocated: 0,
    totalUsed: 0,
    totalRemaining: 0,
    pendingRequests: 0,
    leavePolicyCount: 0,
    year: year ?? DateTime.now().year,
    policies: const [],
  );
}

class LeaveSummaryService {
  LeaveSummaryService._();
  static final LeaveSummaryService instance = LeaveSummaryService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<LeaveSummary> fetch({int? year, String? userEmail}) async {
    final currentYear = year ?? DateTime.now().year;
    try {
      debugPrint('[LeaveSummary] Fetching leave summary for year: $currentYear');
      final res = await _supabase.rpc(
        'get_my_leave_summary',
        params: {'_year': currentYear},
      );

      debugPrint('[LeaveSummary] Raw RPC response: $res');
      debugPrint('[LeaveSummary] Response type: ${res.runtimeType}');

      if (res == null) {
        debugPrint('[LeaveSummary] Response is null. Attempting fallback with userEmail: $userEmail');
        if (userEmail != null && userEmail.isNotEmpty) {
          return _fetchFallback(userEmail, currentYear);
        }
        debugPrint('[LeaveSummary] No userEmail for fallback, returning empty');
        return LeaveSummary.empty(currentYear);
      }

      final data = Map<String, dynamic>.from(res as Map);
      debugPrint('[LeaveSummary] Parsed data keys: ${data.keys.toList()}');

      final balancesRes = (data['balances'] as List?) ?? const [];
      final policiesRes = (data['types'] as List?) ?? const [];
      final pendingCount = (data['pending'] as num?)?.toInt() ?? 0;

      debugPrint('[LeaveSummary] balancesRes: $balancesRes');
      debugPrint('[LeaveSummary] policiesRes: $policiesRes');
      debugPrint('[LeaveSummary] pendingCount: $pendingCount');

      final leaveTypeMap = <String, Map<String, dynamic>>{
        for (final p in policiesRes)
          (p as Map)['id'].toString(): Map<String, dynamic>.from(p),
      };

      final Map<String, LeaveSummaryPolicy> policyMap = {};

      if (balancesRes.isNotEmpty) {
        for (final b in balancesRes) {
          final row = Map<String, dynamic>.from(b as Map);
          final policy = leaveTypeMap[row['leave_type_id']?.toString()];
          final pName = (policy?['name'] ?? 'Unnamed Policy').toString();
          final pDays = (policy?['days_allowed'] ?? 0);
          policyMap[pName] = LeaveSummaryPolicy(
            name: pName,
            allocated: ((row['allocated_days'] ?? pDays) as num).toInt(),
            used: ((row['used_days'] ?? 0) as num).toInt(),
            remaining: ((row['remaining_days'] ?? 0) as num).toInt(),
          );
        }
      } else {
        for (final p in policiesRes) {
          final row = Map<String, dynamic>.from(p as Map);
          final name = (row['name'] ?? 'Unnamed Policy').toString();
          final days = ((row['days_allowed'] ?? 0) as num).toInt();
          policyMap[name] = LeaveSummaryPolicy(
            name: name,
            allocated: days,
            used: 0,
            remaining: days,
          );
        }
      }

      int a = 0, u = 0, r = 0;
      for (final p in policyMap.values) {
        a += p.allocated;
        u += p.used;
        r += p.remaining;
      }

      debugPrint('[LeaveSummary] Final totals - allocated: $a, used: $u, remaining: $r');
      debugPrint('[LeaveSummary] Policy count: ${policyMap.length}');
      debugPrint('[LeaveSummary] Policies: ${policyMap.values.toList()}');

      return LeaveSummary(
        totalAllocated: a,
        totalUsed: u,
        totalRemaining: r,
        pendingRequests: pendingCount,
        leavePolicyCount: policyMap.length,
        year: currentYear,
        policies: policyMap.values.toList(),
      );
    } catch (e, st) {
      debugPrint('LeaveSummaryService error: $e');
      debugPrint(st.toString());
      rethrow;
    }
  }

  // Fallback method if RPC returns null
  // Queries leave data directly using employee email
  Future<LeaveSummary> _fetchFallback(String userEmail, int year) async {
    try {
      debugPrint('[LeaveSummary] Using fallback fetch with email: $userEmail');

      // Get employee record by email
      final emp = await _supabase
          .from('employee_records')
          .select('id, organization_id')
          .eq('email', userEmail)
          .maybeSingle();

      if (emp == null) {
        debugPrint('[LeaveSummary] Employee not found for email: $userEmail');
        return LeaveSummary.empty(year);
      }

      final empId = emp['id'];
      debugPrint('[LeaveSummary] Found employee: $empId');

      // Get leave balances for this employee
      final balances = await _supabase
          .from('leave_balances')
          .select('leave_type_id, allocated_days, used_days, remaining_days')
          .eq('employee_id', empId)
          .eq('year', year);

      debugPrint('[LeaveSummary] Fallback balances: $balances');

      // Get leave types
      final leaveTypes = await _supabase
          .from('leave_types')
          .select('id, name, days_allowed')
          .eq('organization_id', emp['organization_id']);

      debugPrint('[LeaveSummary] Fallback leave_types: $leaveTypes');

      final leaveTypeMap = <String, Map<String, dynamic>>{
        for (final p in leaveTypes ?? [])
          (p as Map)['id'].toString(): Map<String, dynamic>.from(p),
      };

      final Map<String, LeaveSummaryPolicy> policyMap = {};

      // Process balances
      final balancesRes = balances ?? [];
      if (balancesRes.isNotEmpty) {
        for (final b in balancesRes) {
          final row = Map<String, dynamic>.from(b as Map);
          final policy = leaveTypeMap[row['leave_type_id']?.toString()];
          final pName = (policy?['name'] ?? 'Unnamed Policy').toString();
          final pDays = (policy?['days_allowed'] ?? 0);
          policyMap[pName] = LeaveSummaryPolicy(
            name: pName,
            allocated: ((row['allocated_days'] ?? pDays) as num).toInt(),
            used: ((row['used_days'] ?? 0) as num).toInt(),
            remaining: ((row['remaining_days'] ?? 0) as num).toInt(),
          );
        }
      } else {
        // No balances, use leave types
        for (final p in leaveTypeMap.values) {
          final name = (p['name'] ?? 'Unnamed Policy').toString();
          final days = ((p['days_allowed'] ?? 0) as num).toInt();
          policyMap[name] = LeaveSummaryPolicy(
            name: name,
            allocated: days,
            used: 0,
            remaining: days,
          );
        }
      }

      int a = 0, u = 0, r = 0;
      for (final p in policyMap.values) {
        a += p.allocated;
        u += p.used;
        r += p.remaining;
      }

      debugPrint('[LeaveSummary] Fallback totals - allocated: $a, used: $u, remaining: $r');

      return LeaveSummary(
        totalAllocated: a,
        totalUsed: u,
        totalRemaining: r,
        pendingRequests: 0, // Fallback doesn't get pending count
        leavePolicyCount: policyMap.length,
        year: year,
        policies: policyMap.values.toList(),
      );
    } catch (e, st) {
      debugPrint('[LeaveSummary] Fallback error: $e');
      debugPrint(st.toString());
      return LeaveSummary.empty(year);
    }
  }
}
