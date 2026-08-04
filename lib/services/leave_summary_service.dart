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

  Future<LeaveSummary> fetch({int? year}) async {
    final currentYear = year ?? DateTime.now().year;
    try {
      final res = await _supabase.rpc(
        'get_my_leave_summary',
        params: {'_year': currentYear},
      );
      if (res == null) return LeaveSummary.empty(currentYear);

      final data = Map<String, dynamic>.from(res as Map);
      final balancesRes = (data['balances'] as List?) ?? const [];
      final policiesRes = (data['types'] as List?) ?? const [];
      final pendingCount = (data['pending'] as num?)?.toInt() ?? 0;

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
}
