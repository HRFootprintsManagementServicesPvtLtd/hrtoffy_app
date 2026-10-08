import '../core/api/json_case.dart';
import 'base_repository.dart';

/// Gratuity nominees, personal documents and insurance policies shown on the profile.
/// Rows are normalised to the snake_case columns the profile UI reads.
class ProfileRepository extends BaseRepository {
  ProfileRepository({super.auth});

  /// `GET /organizations/:orgId/employees/:employeeId/nominees`, newest first.
  Future<List<Map<String, dynamic>>> nominees() async {
    final data = await api.get(orgPath('/employees/$employeeId/nominees'));
    final rows = asMapList(data).map((r) => Map<String, dynamic>.from(snakeKeys(r) as Map)).toList();
    rows.sort((a, b) => (asDate(b['created_at']) ?? DateTime(0)).compareTo(asDate(a['created_at']) ?? DateTime(0)));
    return rows;
  }

  /// `PUT /organizations/:orgId/nominees/:id` (the backend only allows this while the nominee is still pending).
  Future<void> updateNominee(String id, {required String name, required String relationship, required double sharePercent}) async {
    await api.put(orgPath('/nominees/$id'), body: {
      'nomineeName': name,
      'relationship': relationship,
      'sharePercent': sharePercent,
    });
  }

  /// `GET /organizations/:orgId/employees/:employeeId/documents` (a bare `{items: [...]}` body), newest first.
  Future<List<Map<String, dynamic>>> documents() async {
    final data = await api.get(orgPath('/employees/$employeeId/documents'));
    final rows = asMapList(data).map((r) => Map<String, dynamic>.from(snakeKeys(r) as Map)).toList();
    rows.sort((a, b) => (asDate(b['uploaded_at']) ?? DateTime(0)).compareTo(asDate(a['uploaded_at']) ?? DateTime(0)));
    return rows;
  }

  /// `POST /organizations/:orgId/employees/:employeeId/documents`.
  /// [fileRef] is the `bucket/path` reference returned by the file upload.
  Future<void> addDocument({required String name, required String type, required String fileRef, int? size}) async {
    await api.post(orgPath('/employees/$employeeId/documents'), body: {
      'documentType': type,
      'documentName': name,
      'fileUrl': fileRef,
      if (size != null) 'fileSize': size,
    });
  }

  /// `DELETE /organizations/:orgId/employees/:employeeId/documents/:documentId`
  Future<void> deleteDocument(String documentId) async {
    await api.delete(orgPath('/employees/$employeeId/documents/$documentId'));
  }

  /// `GET /organizations/:orgId/insurance/policies?employeeId=`
  Future<List<Map<String, dynamic>>> insurancePolicies() async {
    final data = await api.get(orgPath('/insurance/policies'), query: {'employeeId': employeeId});
    return asMapList(data);
  }
}
