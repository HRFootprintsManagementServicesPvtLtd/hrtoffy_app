# Employee Benefits & Claims: status

Source-level only. Nothing here was run, tested, or checked against a deployed AWS environment.

## Backend evidence (hrtoffy-backend-mobile-aws, src/modules/benefits)
- `GET /organizations/:orgId/benefits/claims?employeeId=` (employees without compensation.view/manage are forced to their own claims server-side),
  `GET .../claims/:claimId` (own claim only, else "not found"), `GET .../benefits/catalog`, `POST .../benefits/claims`.
  `GET /organizations/:orgId/grade-structures/limits/:gradeCode` is in `grade-structures.routes.ts`.
- `POST` body: `{employeeId, benefitId, claimedAmount, description, supportingDocuments?}`. The server accepts another employee's id only
  for compensation.manage and takes status, dates, payment mode, month/year, manager and submitter itself. It checks only amount > 0 and that
  the benefit is in the organization. **It does not enforce the yearly/grade limit, eligibility, the benefit's max amount, or the validity of
  `supportingDocuments` references.**
- Commit `ba743e3` ("persist payroll claim metadata": payment_mode='payroll', claim_month/year, manager) exists ONLY on the local branch
  `benefits-claim-fix` of that checkout. It is on no other local or remote branch, so it is not in origin/main or any deploy branch.
  Without it a created claim is never picked up by payroll.
- The Files API (`POST /organizations/:orgId/files`, bucket `claim-documents`, own employee only) exists only in `hrtoffy-g1-deploy`
  (`src/modules/files`, registered in its app.ts), not in the checkout that has the claim fix. That checkout's claim POST has no payroll fix.

## App
- Done: catalog, own claims list, claim detail (`BenefitsRepository.claim`), `submitClaim`, form wired (no attachment), yearly-usage
  calculation (approved else claimed amount of non-rejected claims with `claim_year` = this year), no invented default limit.
- **Submission is OFF**: `kBenefitClaimSubmissionEnabled = false` in `lib/screens/benefits_screen.dart`. Enable only after the `ba743e3` fix is
  verified deployed.
- Attachments: not implemented (no checkout has both the Files API and the claim fix; the server does not validate document references).

## Unresolved
- Eligibility, grade limit and yearly limit are advisory in the app only; no server enforcement exists in source.
- Claims created before the fix have no `claim_year` and are not counted toward the yearly total.
- `claim_date` is server time in UTC; the month/year used by payroll follows it.
