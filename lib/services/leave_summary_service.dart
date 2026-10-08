// Single source of truth for the "leave summary" numbers shown on the
// Dashboard leave-balance card and on the Leave screen summary cards.
//
// It reads the signed-in employee's balances and pending requests from the
// HR Toffy API (see LeaveRepository) and normalises them into a shape both
// screens can consume without duplicating business logic.

import 'package:flutter/foundation.dart';

import '../core/api/json_case.dart';
import '../repositories/leave_repository.dart';

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
  LeaveSummaryService._() : _injected = null;

  /// For tests: a service that reads through [repository].
  @visibleForTesting
  LeaveSummaryService.withRepository(LeaveRepository repository) : _injected = repository;

  static final LeaveSummaryService instance = LeaveSummaryService._();

  final LeaveRepository? _injected;
  LeaveRepository? _lazy;

  /// Created on first use: the repository needs a signed-in session.
  LeaveRepository get _repo => _injected ?? (_lazy ??= LeaveRepository());

  Future<LeaveSummary> fetch({int? year}) async {
    final currentYear = year ?? DateTime.now().year;
    try {
      final balances = await _repo.balances(year: currentYear);
      // A failing pending count must not blank the balances.
      var pending = 0;
      try {
        pending = await _repo.pendingCount();
      } catch (e) {
        debugPrint('LeaveSummaryService pending count error: $e');
      }

      // One entry per policy name (same as before: duplicates collapse).
      final Map<String, LeaveSummaryPolicy> policyMap = {};

      if (balances.isNotEmpty) {
        for (final b in balances) {
          final name = b.name.isEmpty ? 'Unnamed Policy' : b.name;
          policyMap[name] = LeaveSummaryPolicy(
            name: name,
            allocated: b.allocated.toInt(),
            used: b.used.toInt(),
            remaining: b.remaining.toInt(),
          );
        }
      } else {
        // No balance rows yet: show what the organisation's leave policies would give.
        List<Map<String, dynamic>> policies = const [];
        try {
          policies = await _repo.policies(year: currentYear);
        } catch (e) {
          debugPrint('LeaveSummaryService policies error: $e');
        }
        for (final row in policies) {
          final name = (row['name'] ?? 'Unnamed Policy').toString();
          final days = asInt(row['days_allowed']);
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
        pendingRequests: pending,
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
