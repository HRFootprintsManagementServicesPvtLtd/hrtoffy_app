# Group 2 (Leave) live shape check on staging (READ-ONLY: GET requests only, plus the normal sign-in).
# Run it yourself: it asks for the staging test account's email and password (hidden). Nothing is created, changed or deleted.
# Prints HTTP status, field NAMES, counts and PASS/FAIL checks - never tokens, passwords, names, emails, reasons or dates.
$base = 'https://api.hrtoffy.in'

function Call([string]$method, [string]$path, $body, [string]$token) {
  $h = @{ 'Content-Type' = 'application/json' }
  if ($token) { $h['Authorization'] = "Bearer $token" }
  $a = @{ Uri = "$base$path"; Method = $method; Headers = $h; UseBasicParsing = $true }
  if ($body) { $a['Body'] = ($body | ConvertTo-Json -Depth 6) }
  try { $r = Invoke-WebRequest @a; return @{ status = [int]$r.StatusCode; json = ($r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue) } }
  catch {
    $code = 0; $j = $null
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      try { $s = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $j = ($s.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue) } catch {}
    }
    return @{ status = $code; json = $j }
  }
}
function Names($x) { if ($x -is [pscustomobject]) { return ($x.PSObject.Properties.Name -join ', ') } else { return '(not an object)' } }
function Check([bool]$ok, [string]$what) { Write-Host ("  [{0}] {1}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $what) }

$email = Read-Host 'Staging test account email'
$sec = Read-Host 'Password (hidden)' -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

$d = Call 'POST' '/auth/discover-tenants' @{ email = $email } $null
$org = @($d.json.organizations)[0]
if (-not $org) { Write-Host 'No organization returned; stopping.'; return }
$l = Call 'POST' '/auth/login' @{ organizationId = $org.id; email = $email; authMethod = 'password'; credentials = @{ password = $pw } } $null
$pw = $null
Check ($l.status -eq 200) "authentication succeeds (HTTP $($l.status))"
if ($l.status -ne 200) { return }
$tok = $l.json.accessToken
$o = $org.id
$ru = Call 'GET' '/auth/resolve-user' $null $tok
$emp = $ru.json.data.employeeId
Check ([bool]$emp) 'session carries an employee id'
if (-not $emp) { return }
$year = (Get-Date).Year

Write-Host "`n1) GET /organizations/<org>/employees/<emp>/leaves"
$r = Call 'GET' "/organizations/$o/employees/$emp/leaves" $null $tok
Write-Host "  HTTP $($r.status)"
Check ($r.status -eq 200) 'HTTP 200'
if ($r.status -eq 200) {
  $j = $r.json
  Check ($j.success -eq $true) 'success = true'
  Check ($null -ne $j.data) 'data present'
  Write-Host "  data keys: $(Names $j.data)"
  Check (($j.data.PSObject.Properties.Name -contains 'items') -and ($j.data.PSObject.Properties.Name -contains 'total') -and ($j.data.PSObject.Properties.Name -contains 'limit') -and ($j.data.PSObject.Properties.Name -contains 'offset')) 'data = { items, total, limit, offset }'
  $items = @($j.data.items)
  Write-Host "  items: $($items.Count)   total=$($j.data.total) limit=$($j.data.limit) offset=$($j.data.offset)"
  if ($items.Count -gt 0) {
    Write-Host "  item keys: $(Names $items[0])"
    $want = 'id','leave_type','from_date','to_date','total_days','reason','status','manager_name','manager_email','created_at'
    $have = $items[0].PSObject.Properties.Name
    Check (-not ($want | Where-Object { $have -notcontains $_ })) 'item has the expected leave fields'
    Check (-not ($items | Where-Object { $_.from_date -notmatch '^\d{4}-\d{2}-\d{2}$' })) 'from_date is YYYY-MM-DD'
    Write-Host ("  statuses seen: " + (($items | ForEach-Object { $_.status } | Sort-Object -Unique) -join ', '))
    Check (-not ($items | Where-Object { $_.PSObject.Properties.Name -contains 'employee_id' -and $_.employee_id -ne $emp })) 'no item carries another employee id'
  } else {
    Write-Host '  (this account has no leave applications; field check skipped)'
  }
}

Write-Host "`n2) Negative check: someone else's id must be refused (random id, then the same id is NOT this employee)"
$rand = [guid]::NewGuid().ToString()
$n = Call 'GET' "/organizations/$o/employees/$rand/leaves" $null $tok
Write-Host "  HTTP $($n.status)"
Check ($n.status -eq 404) 'a foreign / unknown employee id returns 404'
$n2 = Call 'GET' "/organizations/$o/employees/$rand/leaves" $null ''
Check (($n2.status -eq 401) -or ($n2.status -eq 403)) "no token is refused (HTTP $($n2.status))"

Write-Host "`n3) GET /organizations/<org>/employees/<emp>/leave-balances?year=$year"
$b = Call 'GET' "/organizations/$o/employees/$emp/leave-balances?year=$year" $null $tok
Write-Host "  HTTP $($b.status)"
Check ($b.status -eq 200) 'HTTP 200'
if ($b.status -eq 200) {
  $rows = if ($b.json.data -is [array]) { @($b.json.data) } else { @($b.json.data.items) }
  Write-Host "  success=$($b.json.success)   rows: $($rows.Count)"
  if ($rows.Count -gt 0) {
    Write-Host "  row keys: $(Names $rows[0])"
    $wantB = 'leave_type_id','leave_type_name','allocated_days','used_days','remaining_days','year'
    $haveB = $rows[0].PSObject.Properties.Name
    Check (-not ($wantB | Where-Object { $haveB -notcontains $_ })) 'row has the expected balance fields'
  }
}
Write-Host "`nDone. Only GET requests (and the sign-in) were sent."
