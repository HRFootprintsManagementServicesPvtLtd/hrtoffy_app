import '../core/api/api_client.dart';
import '../core/api/json_case.dart';
import 'base_repository.dart';

/// What is known about which surveys the caller has answered.
class SurveyCompletion {
  const SurveyCompletion({required this.submittedAt, required this.unknown});

  /// Survey id -> the submission time the server reported (may be null), for surveys the caller answered.
  final Map<String, String?> submittedAt;

  /// Surveys whose lookup failed: neither completed nor confirmed open.
  final Set<String> unknown;

  bool isCompleted(String surveyId) => submittedAt.containsKey(surveyId);
}

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

  /// The active surveys the signed-in employee can see, for the employee Surveys screen:
  /// `GET /organizations/:orgId/surveys?status=active` (the surveys module). Its audience rule treats a survey with no
  /// target (`target_audience` null or `company_wide`) as open to everyone. The engagement list
  /// ([activeSurveys]) filters on `target_departments` being an EMPTY array, which silently drops surveys whose array is
  /// NULL, so it is only the fallback when the surveys module cannot answer.
  Future<List<Map<String, dynamic>>> mySurveys() async {
    try {
      final data = await api.get(orgPath('/surveys'), query: {'status': 'active', 'limit': 200});
      return asMapList(data);
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isNetworkError) rethrow;
      return activeSurveys();
    }
  }

  /// Recent recognitions, newest first: `GET /organizations/:orgId/engagement/recognition?limit=50` (read needs
  /// ENGAGEMENT_VIEW, which every member has; giving recognition needs ENGAGEMENT_MANAGE and is NOT used here).
  /// Rows carry `from_employee`/`to_employee` (`full_name`...), `recognition_badges` (`badge_name`, `icon_emoji`),
  /// `recognition_message`, `points`, `visibility`. The server already hides private ones from everyone but the two people
  /// involved; the same rule is applied again here.
  Future<List<Map<String, dynamic>>> recognitions() async {
    final data = await api.get(orgPath('/engagement/recognition'), query: {'limit': 50});
    final me = user.employeeId;
    return asMapList(data).where((r) {
      if (r['visibility']?.toString() != 'private') return true;
      if (me == null) return false;
      return r['given_by']?.toString() == me || r['given_to']?.toString() == me;
    }).toList();
  }

  /// Active recognition badges: `GET /organizations/:orgId/engagement/recognition/badges` (`id`, `badge_name`,
  /// `icon_emoji`, `points_value`; the server returns active ones only).
  Future<List<Map<String, dynamic>>> badges() async {
    final data = await api.get(orgPath('/engagement/recognition/badges'));
    return asMapList(data);
  }

  /// `POST /organizations/:orgId/engagement/recognition`. The body is exactly the fields the route accepts
  /// (`given_to` = the colleague's employee id, `badge_id`, `recognition_message`, `visibility`, `points`); the giver is
  /// set by the server from the session. Until the backend allows managers to give recognition this answers 403.
  Future<void> giveRecognition({
    required String givenTo,
    required String badgeId,
    required String message,
    String visibility = 'public',
    int? points,
  }) async {
    await api.post(
      orgPath('/engagement/recognition'),
      body: {
        'given_to': givenTo,
        'badge_id': badgeId,
        'recognition_message': message,
        'visibility': visibility,
        if (points != null) 'points': points,
      },
    );
  }

  /// Today's birthdays and work anniversaries: `GET /organizations/:orgId/dashboard/celebrations`
  /// (`birthdays`, `anniversaries` with `yearsCompleted`). Each result has `full_name`, `kind` ('birthday' or
  /// 'anniversary') and, for anniversaries, `years`.
  Future<List<Map<String, dynamic>>> celebrations() async {
    final data = await api.get(orgPath('/dashboard/celebrations'));
    final map = data is Map ? data : const {};
    return [
      for (final b in asMapList(map['birthdays'])) {'full_name': b['full_name'], 'kind': 'birthday'},
      for (final a in asMapList(map['anniversaries']))
        {
          'full_name': a['full_name'],
          'kind': 'anniversary',
          'years': a['years_completed'] ?? a['yearsCompleted'],
        },
    ].where((c) => (c['full_name']?.toString() ?? '').isNotEmpty).toList();
  }

  /// Which of [surveyIds] the caller has already answered, one `GET .../engagement/surveys/:id/my-response` each (that
  /// route answers `null` when the caller has not responded and the response row, with `submitted_at`, when they have).
  /// Lookups run [concurrency] at a time; a survey whose lookup fails is reported in [SurveyCompletion.unknown], never
  /// as completed or as not completed. Beyond [maxSurveys] surveys the rest are unknown.
  Future<SurveyCompletion> surveyCompletion(
    Iterable<String> surveyIds, {
    int concurrency = 4,
    int maxSurveys = 100,
  }) async {
    final all = surveyIds.toList();
    final ids = all.take(maxSurveys).toList();
    final submittedAt = <String, String?>{};
    final unknown = <String>{...all.skip(maxSurveys)};
    var next = 0;
    Future<void> worker() async {
      while (next < ids.length) {
        final id = ids[next++];
        try {
          final r = await api.get(orgPath('/engagement/surveys/$id/my-response'));
          if (r is Map) submittedAt[id] = (r['submitted_at'] ?? r['submittedAt'])?.toString();
        } catch (_) {
          unknown.add(id);
        }
      }
    }

    await Future.wait(List.generate(concurrency < 1 ? 1 : concurrency, (_) => worker()));
    return SurveyCompletion(submittedAt: submittedAt, unknown: unknown);
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
