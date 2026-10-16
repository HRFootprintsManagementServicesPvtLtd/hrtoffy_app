import '../core/api/json_case.dart';
import 'base_repository.dart';

/// Internal job openings and the signed-in person's own applications to them.
class RecruitmentRepository extends BaseRepository {
  RecruitmentRepository({super.auth});

  /// `GET /organizations/:orgId/recruitment/internal-jobs` - open, internal postings (a plain list: `id`, `job_title`,
  /// `department`, `location`, `employment_type`, `salary_min`, `salary_max`, `number_of_positions`,
  /// `internal_deadline`, `job_description`, `created_at`). Open to every member of the organization.
  Future<List<Map<String, dynamic>>> internalJobs() async {
    final data = await api.get(orgPath('/recruitment/internal-jobs'));
    return asMapList(data);
  }

  /// `GET /organizations/:orgId/recruitment/internal-jobs/my-applications` - the caller's own internal applications
  /// (`job_id`, `status`, `job_openings`). Returns the ids of the jobs the caller has applied to.
  Future<Set<String>> appliedJobIds() async {
    final data = await api.get(
      orgPath('/recruitment/internal-jobs/my-applications'),
    );
    return {
      for (final a in asMapList(data))
        if ((a['job_id']?.toString() ?? '').isNotEmpty) a['job_id'].toString(),
    };
  }

  /// `POST /organizations/:orgId/recruitment/internal-jobs/:jobId/apply` - the caller applies for themselves (the server
  /// takes the applicant from the session; membership is the only permission it needs).
  Future<void> applyInternal(String jobId) async {
    await api.post(
      orgPath('/recruitment/internal-jobs/$jobId/apply'),
      body: {},
    );
  }
}
