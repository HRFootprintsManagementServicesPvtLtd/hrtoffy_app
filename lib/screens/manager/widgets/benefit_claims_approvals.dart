import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../repositories/approvals_repository.dart';
import '../../../repositories/benefits_repository.dart';
import 'benefit_approvals_panel.dart';
import 'inbox_approvals_panel.dart';

/// A manager's benefit claim approvals in two lists: ESI claims (decided through the ESI routes, which scope them to the
/// manager's team) and the other benefit claims, which are decided from the approval inbox (the claims waiting at the
/// manager's step).
class BenefitClaimsApprovals extends StatelessWidget {
  const BenefitClaimsApprovals({super.key, this.benefitsRepository, this.approvalsRepository});

  final BenefitsRepository? benefitsRepository;
  final ApprovalsRepository? approvalsRepository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            labelStyle: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [Tab(text: 'ESI claims'), Tab(text: 'Other claims')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                BenefitApprovalsPanel(benefitsRepository: benefitsRepository, showGeneralSlot: false),
                InboxApprovalsPanel(module: 'benefits', repository: approvalsRepository),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
