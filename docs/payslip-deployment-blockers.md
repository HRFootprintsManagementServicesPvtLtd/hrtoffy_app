# Payslip: open items before deployment

Status: source-reviewed only. Nothing here has been tested, deployed, or verified against AWS or production.

## Blocker: salary authorization is unverified
- The backend payslip PDF route (`GET /organizations/:orgId/reports/payslip-pdf?payslipId=`, in `hrtoffy-backend-mobile-aws`)
  relies on the database function `public.can_decrypt_employee_salary(employee_id)` to decide who may read another
  employee's payslip.
- Its definition is not in any local backend checkout (no migration, fixture, grant or policy defines it). Who passes it is **unknown**.
- The employee release gate (`ownPayslipIsReleased`) only runs when the database reports the payslip as the caller's own.
  Whether a caller without `payroll.view` can pass the function for someone else's payslip, and so skip the gate, is **unresolved**.
- Resolve by inspecting the live definition (`pg_get_functiondef`) before any deployment. Do not treat salary authorization as verified until then.

## Payslip history limit
- `GET /organizations/:orgId/payroll/employees/:employeeId/payslips` takes no query parameters and returns at most the 12 most
  recent released payslips (selected from the 60 newest rows). There is no paging or date filter for employees; the filtered list
  route needs `payroll.view`.
- The app shows "only 12 most recent" for periods older than the oldest listed one when the list is full, instead of "none".
  Older payslips are not reachable until the backend supports paging.

## PDF storage
- PDFs are written **unencrypted** to `<app cache>/payslips/` (private to the app, sanitized names). The app does not delete them;
  the OS may clear the cache, which is not guaranteed. They are removed on uninstall or clearing app storage.
- "Bulk Download" fetches the newest 3/6/12 released payslips and lists them; the employee opens one (viewer) or uses "Save a
  copy" (system save dialog, via `file_picker`) to keep it. Nothing is reported saved until a file was actually written. The
  private cache copy is still unencrypted and is removed after a delay.
- The app reads a payslip ONLY through `GET /reports/payslip-pdf?payslipId=` (id from the employee's own released list), when the
  employee asks to view or save it; nothing is requested when a month is selected. It does NOT call `payslip-document`: that route
  is not on the deployed server (it exists only as uncommitted backend code), so the request fell into the generic
  `/reports/:reportId` route, which needs `reports.view` and answered every employee with a 403 that had nothing to do with salary.
  A 403 from `payslip-pdf` is now the server's real answer (not yours, not released, or salary not readable by the caller; one
  answer so ids cannot be probed). Net pay and title come from that response; a net pay of 0 is shown as 0.
- `tool/probe_payslip.ps1` (read-only, run by the owner against a confirmed non-production environment) records the real
  status of the list and PDF routes for a test employee.
