import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import '../../../repositories/benefits_repository.dart';
import 'benefit_approvals_panel.dart';
import 'benefit_general_approvals_panel.dart';

/// A manager's benefit claim approvals in two lists: ESI claims (decided through the ESI routes, which scope them to the
/// manager's team) and the other benefit claims ([BenefitGeneralApprovalsPanel], split with the approval engine's row-meta).
class BenefitClaimsApprovals extends StatelessWidget {
  const BenefitClaimsApprovals({
    super.key,
    this.benefitsRepository,
    this.approvalsRepository,
    this.initialTab = 0,
  });

  final BenefitsRepository? benefitsRepository;
  final ApprovalsRepository? approvalsRepository;

  /// 0 = ESI claims, 1 = other claims.
  final int initialTab;

  /// ESI claims plus general claims the caller may decide now. Throws when either could not be determined.
  static Future<int> countActionable({
    BenefitsRepository? benefitsRepository,
    ApprovalsRepository? approvalsRepository,
  }) async {
    final repo = benefitsRepository ?? BenefitsRepository();
    final esi = await BenefitApprovalsPanel.countActionable(
      benefitsRepository: repo,
    );
    final general = await BenefitGeneralApprovalsPanel.countActionable(
      benefitsRepository: repo,
      approvalsRepository: approvalsRepository,
    );
    return esi + general;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            labelStyle: GoogleFonts.montserrat(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'ESI claims'),
              Tab(text: 'Other claims'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                BenefitApprovalsPanel(benefitsRepository: benefitsRepository),
                BenefitGeneralApprovalsPanel(
                  benefitsRepository: benefitsRepository,
                  approvalsRepository: approvalsRepository,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
