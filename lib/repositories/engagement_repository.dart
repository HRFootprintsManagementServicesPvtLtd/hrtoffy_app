import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';

/// Announcements, events, FAQs and surveys. These endpoints return raw
/// snake_case rows, so the UI reads them unchanged.
class EngagementRepository extends BaseRepository {
  EngagementRepository({super.auth});

  /// `GET /organizations/:orgId/engagement/announcements`
  ///
  /// The server already limits non-managers to live, published announcements aimed
  /// at their department. Managers can also receive drafts and inactive ones, so the
  /// "active only" rule the old query applied is kept here.
  Future<List<Map<String, dynamic>>> announcements() async {
    final data = await api.get(orgPath('/engagement/announcements'), query: {'limit': 200});
    return asMapList(data).where((a) {
      if (a['is_active'] == false) return false;
      final status = a['status']?.toString();
      return status == null || status == 'published';
    }).toList();
  }

  /// `GET /organizations/:orgId/engagement/events`, soonest first (the old query's order).
  /// Each event carries `created_by`, which the backend stores as the creator's USER id
  /// (not the employee id); compare against both.
  Future<List<Map<String, dynamic>>> events() async {
    final data = await api.get(orgPath('/engagement/events'), query: {'limit': 200});
    final list = asMapList(data);
    list.sort((a, b) => (asDate(a['event_date']) ?? DateTime(0)).compareTo(asDate(b['event_date']) ?? DateTime(0)));
    return list;
  }

  /// `GET /organizations/:orgId/faqs`, active only, grouped by category then newest first.
  Future<List<Map<String, dynamic>>> faqs() async {
    final data = await api.get(orgPath('/faqs'));
    final list = asMapList(data).where((f) => f['is_active'] != false).toList();
    list.sort((a, b) {
      final c = (a['category']?.toString() ?? '').compareTo(b['category']?.toString() ?? '');
      if (c != 0) return c;
      return (asDate(b['created_at']) ?? DateTime(0)).compareTo(asDate(a['created_at']) ?? DateTime(0));
    });
    return list;
  }

  /// `GET /organizations/:orgId/engagement/surveys?status=active`
  Future<List<Map<String, dynamic>>> activeSurveys() async {
    final data = await api.get(orgPath('/engagement/surveys'), query: {'status': 'active', 'limit': 200});
    return asMapList(data);
  }

  /// Ids of surveys the caller has already answered:
  /// `GET /organizations/:orgId/engagement/surveys/my-responses`.
  Future<Set<String>> completedSurveyIds() async {
    final data = await api.get(orgPath('/engagement/surveys/my-responses'));
    return asMapList(data).map((r) => r['survey_id'].toString()).toSet();
  }

  /// Submits answers. Throws `ApiException(409, ...)` when the caller already answered
  /// this survey (the old insert failed with Postgres 23505 in that case).
  ///
  /// `GET .../surveys/:id/my-response` is checked first because
  /// `POST .../surveys/:id/respond` would otherwise silently overwrite the earlier answers.
  Future<void> submitSurveyResponse(String surveyId, List<Map<String, dynamic>> responses) async {
    final existing = await api.get(orgPath('/engagement/surveys/$surveyId/my-response'));
    if (existing != null) {
      throw const ApiException(409, 'You have already submitted this survey.', code: 'ALREADY_SUBMITTED');
    }
    await api.post(orgPath('/engagement/surveys/$surveyId/respond'), body: {'responses': responses});
  }
}
