import '../core/api/api_client.dart';
import 'base_repository.dart';

/// The employee's organization: name and logo.
class OrganizationRepository extends BaseRepository {
  OrganizationRepository({super.auth});

  /// `{id, name, logo_url}` - the pieces of the old `organizations` row the app uses.
  ///
  /// Name comes from `GET /organizations/:orgId/info`, the logo from
  /// `GET /organizations/:orgId/branding`. A branding failure (e.g. the caller's
  /// role cannot read it) just means no logo; it never blocks the name.
  Future<Map<String, dynamic>> getOrganization() async {
    final info = await api.get(orgPath('/info'));
    String? logo;
    try {
      final branding = await api.get(orgPath('/branding'));
      if (branding is Map) logo = branding['logoUrl']?.toString();
    } on ApiException {
      logo = null;
    }
    final infoMap = info is Map ? info : const {};
    return {
      'id': infoMap['organization_id']?.toString() ?? organizationId,
      'name': infoMap['organization_name']?.toString(),
      'logo_url': (logo == null || logo.isEmpty) ? null : logo,
    };
  }
}
