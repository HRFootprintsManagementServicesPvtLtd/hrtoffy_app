# Payslip live check. It changes no payslip, employee or salary data (the only requests besides sign-in are GETs), BUT it
# is not free of server-side side effects:
#   * signing in creates a server session and a refresh token for the test account;
#   * a PDF request may append an audit-log entry for that employee (the server logs PAYSLIP_PDF_DOWNLOADED on success and
#     PAYSLIP_PDF_DENIED on a refusal).
# Run it yourself, ONLY against an environment the owner has confirmed is non-production, with a dedicated test employee
# who has at least one released payslip. It asks for the account's email and password (hidden) and never saves them.
#
# It prints, per request: the HTTP status, and for a failure only an error CODE that is on a fixed allowlist (anything else
# prints "(not on the allowlist)"). It never prints server error text, tokens, the password, payslip ids, months or years,
# amounts, names, or any part of the PDF - only whether the returned bytes start with "%PDF-" and how many bytes there are.
#
# What it answers:
#   1. does the list route return this employee's released payslips        (GET payroll/employees/:id/payslips)
#   2. does the PDF route return a real PDF for the newest one              (GET reports/payslip-pdf?payslipId=)
# A 403 on 2 means the server refuses this payslip for this caller (not yours / not released / salary not readable).
# (The app no longer calls `reports/payslip-document`: it is not a route on the deployed server, so the request falls into the
# generic `/reports/:reportId`, which needs reports.view and answers an employee 403 for a reason unrelated to salary.)
$base = 'https://api.hrtoffy.in'

function Call([string]$path, [string]$token) {
  $h = @{ 'Content-Type' = 'application/json' }
  if ($token) { $h['Authorization'] = "Bearer $token" }
  try { $r = Invoke-WebRequest -Uri "$base$path" -Method GET -Headers $h -UseBasicParsing; return @{ status = [int]$r.StatusCode; json = ($r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue) } }
  catch {
    $code = 0; $j = $null
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      try { $s = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $j = ($s.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue) } catch {}
    }
    return @{ status = $code; json = $j }
  }
}
function Post([string]$path, $body) {
  try { $r = Invoke-WebRequest -Uri "$base$path" -Method POST -Headers @{ 'Content-Type' = 'application/json' } -Body ($body | ConvertTo-Json -Depth 6) -UseBasicParsing; return @{ status = [int]$r.StatusCode; json = ($r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue) } }
  catch { $c = 0; if ($_.Exception.Response) { $c = [int]$_.Exception.Response.StatusCode }; return @{ status = $c; json = $null } }
}
$SafeErrorCodes = @('UNAUTHORIZED', 'FORBIDDEN', 'NOT_FOUND', 'VALIDATION_ERROR', 'BAD_REQUEST', 'INTERNAL_ERROR', 'TOKEN_EXPIRED', 'RATE_LIMITED', 'SERVICE_UNAVAILABLE')
function Summary($r) {
  # Only a code from the allowlist is ever shown; the server's error text is never printed.
  $e = $r.json.error
  $code = if ($e -is [string]) { '' } else { "$($e.code)".ToUpper() }
  if (-not $code) { return 'no error code returned' }
  if ($SafeErrorCodes -contains $code) { return "error code: $code" }
  return 'error code: (not on the allowlist)'
}

$email = Read-Host 'Test employee email'
$sec = Read-Host 'Password (hidden)' -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$d = Post '/auth/discover-tenants' @{ email = $email }
$org = @($d.json.organizations)[0]
if (-not $org) { Write-Host 'No organization returned; stopping.'; return }
$l = Post '/auth/login' @{ organizationId = $org.id; email = $email; authMethod = 'password'; credentials = @{ password = $pw } }
$pw = $null
if ($l.status -ne 200) { Write-Host "Login failed (HTTP $($l.status))."; return }
$tok = $l.json.accessToken
$o = $org.id
Write-Host "Signed in. Organization: $($org.name)  (stop here if this is not the intended TEST organization)`n"

$ru = Call '/auth/resolve-user' $tok
$emp = $ru.json.data.employeeId
if (-not $emp) { Write-Host 'No employee id in the session; stopping.'; return }

Write-Host '1) payslip list'
$ls = Call "/organizations/$o/payroll/employees/$emp/payslips" $tok
Write-Host "   HTTP $($ls.status)"
if ($ls.status -ne 200) { Write-Host "   $(Summary $ls)"; return }
$items = if ($ls.json.data -is [array]) { @($ls.json.data) } else { @($ls.json.data.items) }
Write-Host "   released payslips listed: $($items.Count) (the server returns at most 12)"
if ($items.Count -eq 0) { Write-Host '   nothing released for this employee; use an account that has a released payslip.'; return }
$p = $items[0]
$id = $p.id

Write-Host "`n2) PDF route for the newest listed payslip"
$pdf = Call "/organizations/$o/reports/payslip-pdf?payslipId=$id" $tok
Write-Host "   HTTP $($pdf.status)"
if ($pdf.status -eq 200) {
  $b64 = "$($pdf.json.data.base64)"
  if ($b64.Length -eq 0) { Write-Host '   FAIL: 200 but no base64 field' }
  else {
    $bytes = [Convert]::FromBase64String($b64)
    $head = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(5, $bytes.Length))
    Write-Host ("   [{0}] returned bytes start with %PDF-  (size {1} bytes)" -f $(if ($head -eq '%PDF-') { 'PASS' } else { 'FAIL' }), $bytes.Length)
    Write-Host "   response fields: $((@($pdf.json.data.PSObject.Properties.Name)) -join ', ')"
  }
} else { Write-Host "   $(Summary $pdf)" }

Write-Host "`nDone. Only GET requests (and the sign-in) were sent."
