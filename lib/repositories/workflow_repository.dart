import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import 'base_repository.dart';

/// Starts the approval chain of a record the signed-in employee has just created.
///
/// The website does this as a separate step after it saves a request (`initializeWorkflow(module, id)`): the record is
/// stored first, then the approval workflow is initialized for it. The mobile requests are created by their own routes,
/// so the app makes the same second call, `POST /organizations/:orgId/workflows/initialize {moduleName, recordId}`.
/// The server only accepts a record of this organization and treats a repeated call for the same record as a no-op,
/// so it is safe where the server already starts the workflow itself.
///
/// This is deliberately a BEST-EFFORT call: the request has already been created and stored, so a failure here must
/// never be reported as a failed submission. The caller gets `false` and can say that approval routing could not be
/// confirmed.
class WorkflowRepository extends BaseRepository {
  WorkflowRepository({super.auth});

  /// Module names the approval engine knows (the same ones the website passes).
  static const leaves = 'leaves';
  static const benefits = 'benefits';
  static const expenses = 'expenses';

  /// True when the server accepted the initialization; false for any failure (never throws, logs the status only).
  Future<bool> initialize(String moduleName, String? recordId) async {
    final id = recordId?.trim();
    if (id == null || id.isEmpty) return false;
    try {
      await api.post(
        orgPath('/workflows/initialize'),
        body: {'moduleName': moduleName, 'recordId': id},
      );
      return true;
    } catch (e) {
      debugPrint('[Workflow] initialize $moduleName failed: ${e is ApiException ? e.statusCode : e.runtimeType}');
      return false;
    }
  }
}
