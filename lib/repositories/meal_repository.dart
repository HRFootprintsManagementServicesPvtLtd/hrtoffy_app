import '../core/api/json_case.dart';
import 'base_repository.dart';

/// State of the dashboard's meal-voucher card.
class MealVoucherState {
  const MealVoucherState({required this.amount, required this.cutoffHours, required this.order});

  /// Per-meal amount (number).
  final num amount;
  final int cutoffHours;

  /// Today's non-cancelled order (`voucher_code`, `status`, ...), or null if none yet.
  final Map<String, dynamic>? order;
}

class MealRepository extends BaseRepository {
  MealRepository({super.auth});

  /// Returns the card state, or null when the card must stay hidden: meal vouchers
  /// are off for the organization, or HR has not enabled them for this employee.
  ///
  /// `GET /meals/eligibility/me`, `GET /meals/config`, `GET /meals/orders?orderDate=`.
  Future<MealVoucherState?> today(String yyyyMmDd) async {
    final elig = await api.get(orgPath('/meals/eligibility/me'));
    if (elig is! Map || elig['eligible'] != true || elig['employeeEligible'] != true) return null;

    final config = await api.get(orgPath('/meals/config'));
    if (config is! Map || config['is_enabled'] != true) return null;

    final orders = await api.get(orgPath('/meals/orders'), query: {'employeeId': employeeId, 'orderDate': yyyyMmDd});
    final mine = asMapList(orders).where((o) => o['status'] != 'cancelled').toList();
    return MealVoucherState(
      amount: asNum(config['per_meal_amount']) ?? 0,
      cutoffHours: asInt(config['order_cutoff_hours'], 6),
      order: mine.isEmpty ? null : mine.first,
    );
  }

  /// `POST /meals/orders`. Returns true when the order was placed.
  Future<bool> placeOrder(String yyyyMmDd) async {
    final order = await api.post(orgPath('/meals/orders'), body: {'employeeId': employeeId, 'orderDate': yyyyMmDd});
    return order != null;
  }
}
