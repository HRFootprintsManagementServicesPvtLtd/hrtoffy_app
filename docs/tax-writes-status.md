# Tax regime and declaration draft saves: status

Local source verification only (hrtoffy-backend-mobile-aws, `services/payroll`). Nothing was run or deployed-checked.

## Routes used (payroll-tax.routes.ts, repository payroll-tax.repository.ts)
- `PUT /organizations/:orgId/payroll/tax-regime-selections` body `{employeeId, financialYear, regime_type}`.
  Own `employeeId` (employee_records.id) -> only `regime_type`/`selected_at` are kept; another id needs PAYROLL_MANAGE_TAX_CONFIG.
  Upsert key `employee_id_financial_year`. `regime_type` and `financialYear` are NOT validated by the server (app sends `new_regime`/`old_regime`).
- `PUT /organizations/:orgId/payroll/tax-declarations` body `{employeeId, financialYear, deductionTypeId, declared_amount?, is_claimed?, employee_notes?}`
  (top-level ids camelCase, field names snake_case, exactly as the route reads them). Partial updates supported. Own row: only those three
  fields kept; `status` omitted -> new row `draft`, draft/submitted unchanged, approved/rejected -> `submitted` (the app does not edit those).
  Upsert key `employee_id_financial_year_deduction_type_id`. No validation of the amount (negative/non-numeric not rejected by the route).

## Routes NOT used
- `PUT /payroll/me/tax-regime` and `PUT /payroll/me/tax-declarations` (payroll.routes.ts ~3853, ~3932): they upsert on
  `employee_id_organization_id_financial_year` / `employee_id_organization_id_deduction_type_id_financial_year`, which `schema.prisma`
  does not define (the unique keys are `[employee_id, financial_year]` and `[employee_id, financial_year, deduction_type_id]`; the other
  routes in payroll-tax.repository.ts use the correct names). From source these would fail at runtime (hidden by `@ts-ignore`).
  The GETs under `/me/` (findFirst) are fine and are still used for reads.

## Not enforced by the server (source)
Submission window (`declaration_*`/`proof_*` dates are only stored), deduction-type `max_amount`, amount validity, regime/FY format.
The app checks the window, the max and the amount format itself; that is advisory only.

## App
Enabled: choose + Confirm regime; edit claimed/amount/notes and "Save Draft" (one PUT per edited deduction, then reload from the server).
Unavailable: "Submit Declarations for Review" (message only). A saved declaration is a draft and is described as one.
`status` is never sent. Approved/rejected declarations are read-only.

## Unresolved
- Deployment of either route is unverified; the `/me/` PUT defect should be confirmed/fixed in the backend (not done here).
- Whether `status: 'submitted'` is reviewer-visible end to end, and whether any workflow reads drafts: unverified (submit stays off).
- `regime_type` string stored is unvalidated; other consumers' expected values (`old`/`new` vs `old_regime`/`new_regime`) are unverified.
