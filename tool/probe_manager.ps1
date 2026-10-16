# Manager screens live check. READ-ONLY: after the sign-in it makes only GET requests, so it changes no leave, loan, claim,
# expense, chat or any other data. Signing in creates a server session and refresh token for the account, as the app does.
# Run it yourself, ONLY against the staging organisation, with a MANAGER account. It asks for the email and password (hidden)
# and never saves them.
#
# It prints, per request: the HTTP status, the SHAPE of the answer (top-level key names, how many rows, and a count of row
# statuses) and, for a failure, the error code and a short error message. It never prints names, e-mails, amounts, chat text,
# tokens or the password. Ids are never printed either, except that for each approval module it asks the server whether YOU
# may decide the first waiting record ("can-approve") and prints only the yes/no and the reason code.
#
# What it answers: why a manager's approval list is empty or a decision is refused, and what the chat messages look like
# (who sent them, whether names and attachments come back).
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
function Err($r) {
  $e = $r.json.error
  if ($e -is [string]) { return "error: $($e.Substring(0, [Math]::Min(120, $e.Length)))" }
  $m = "$($e.message)"; if ($m.Length -gt 120) { $m = $m.Substring(0, 120) }
  return "error code: $($e.code)  message: $m"
}
# The rows of an answer: a plain array, or { items | executions | requests | messages | rows } inside data.
function Rows($j) {
  $d = $j.data
  if ($null -eq $d) { return @() }
  if ($d -is [array]) { return @($d) }
  foreach ($k in 'items', 'executions', 'requests', 'messages', 'rows', 'claims') { if ($d.PSObject.Properties.Name -contains $k) { return @($d.$k) } }
  return @()
}
function Shape($r) {
  if ($r.status -ne 200) { Write-Host "   HTTP $($r.status)  $(Err $r)"; return @() }
  $rows = Rows $r.json
  $d = $r.json.data
  $top = if ($d -is [array]) { 'array' } elseif ($d) { ($d.PSObject.Properties.Name -join ',') } else { '(no data)' }
  Write-Host "   HTTP 200  data: $top   rows: $($rows.Count)"
  if ($rows.Count -gt 0) {
    Write-Host "   row keys: $(($rows[0].PSObject.Properties.Name) -join ',')"
    foreach ($f in 'status', 'module_name', 'message_type') {
      if ($rows[0].PSObject.Properties.Name -contains $f) {
        $g = $rows | Group-Object { "$($_.$f)" } | ForEach-Object { "$($_.Name)=$($_.Count)" }
        Write-Host "   $f counts: $($g -join '  ')"
      }
    }
  }
  return $rows
}
function CanApprove($org, $tok, $module, $id) {
  $c = Call "/organizations/$org/workflows/module/$module/$id/can-approve" $tok
  if ($c.status -ne 200) { Write-Host "   can-approve ($module): HTTP $($c.status)  $(Err $c)"; return }
  $d = $c.json.data; if (-not $d) { $d = $c.json }
  $parts = foreach ($p in $d.PSObject.Properties) { if ($p.Value -is [bool] -or $p.Value -is [string] -or $p.Value -is [int]) { "$($p.Name)=$($p.Value)" } }
  Write-Host "   can-approve ($module, first record): $($parts -join '  ')"
}

$email = Read-Host 'Manager account email (STAGING)'
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
Write-Host "Signed in. Organization: $($org.name)  (stop here if this is not the STAGING organization)`n"

$ru = Call '/auth/resolve-user' $tok
$me = $ru.json.data
$emp = $me.employeeId
$myUser = $me.id
$orgInfo = @($me.organizations) | Where-Object { $_.id -eq $o } | Select-Object -First 1
Write-Host "0) session   empRole: $($orgInfo.empRole)   isHrRole: $($orgInfo.isHrRole)   employeeId present: $([bool]$emp)"
if (-not $emp) { Write-Host 'No employee id in the session; stopping.'; return }

Write-Host "`n1) team (core-hr list, managerId = me)"
$t = Call "/organizations/$o/employees?managerId=$emp&limit=100&page=1" $tok
$trows = Shape $t
if ($trows.Count -gt 0) {
  $direct = @($trows | Where-Object { $_.managerId -eq $emp }).Count
  Write-Host "   direct reports: $direct   indirect: $($trows.Count - $direct)   total reported: $($t.json.data.total)"
}

Write-Host "`n2) approval counts (dashboard)"
$c = Call "/organizations/$o/dashboard/approval-counts" $tok
if ($c.status -eq 200) { Write-Host "   $((@($c.json.data.PSObject.Properties) | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '  ')" } else { Write-Host "   HTTP $($c.status)  $(Err $c)" }

Write-Host "`n3) approval inbox (workflow executions waiting at your step)"
$ib = Call "/organizations/$o/approvals?limit=100" $tok
$irows = Shape $ib
if ($irows.Count -gt 0) { Write-Host "   modules: $((($irows | Group-Object { $_.module_name } | ForEach-Object { "$($_.Name)=$($_.Count)" })) -join '  ')" }

Write-Host "`n4) team leave applications (new route)"
$lv = Call "/organizations/$o/leaves/team-applications?status=pending,manager_approved,reviewer_approved" $tok
$lrows = Shape $lv
if ($lrows.Count -gt 0) { CanApprove $o $tok 'leaves' $lrows[0].id }

Write-Host "`n5) loans list (no filter)"
$ln = Call "/organizations/$o/loans" $tok
$loans = Shape $ln
if ($loans.Count -gt 0) {
  Write-Host "   rows that are my own: $(@($loans | Where-Object { $_.employee_id -eq $emp }).Count)"
  $open = @($loans | Where-Object { $_.status -in 'pending', 'manager_approved' -and $_.employee_id -ne $emp })
  if ($open.Count -gt 0) { CanApprove $o $tok 'loans' $open[0].id }
}
Write-Host "   (list total reported by the server: $($ln.json.data.total))"

Write-Host "`n6) travel claims list"
$tr = Call "/organizations/$o/travel/claims" $tok
$claims = Shape $tr
if ($claims.Count -gt 0) {
  $open = @($claims | Where-Object { $_.status -in 'pending', 'manager_approved' -and $_.employee_id -ne $emp })
  Write-Host "   waiting claims of other people: $($open.Count)"
  if ($open.Count -gt 0) { CanApprove $o $tok 'travel_claims' $open[0].id }
}

Write-Host "`n7) benefit claims list, and ESI approval list"
$bc = Call "/organizations/$o/benefits/claims" $tok
$bclaims = Shape $bc
if ($bclaims.Count -gt 0) {
  $open = @($bclaims | Where-Object { $_.status -in 'pending', 'manager_approved' -and $_.employee_id -ne $emp })
  Write-Host "   waiting claims of other people: $($open.Count)"
  if ($open.Count -gt 0) { CanApprove $o $tok 'benefits' $open[0].id }
}
$esi = Call "/organizations/$o/benefits/esi/claims" $tok
$null = Shape $esi

Write-Host "`n8) expense claims list"
$ex = Call "/organizations/$o/expenses" $tok
$exrows = Shape $ex
if ($exrows.Count -gt 0) {
  $open = @($exrows | Where-Object { $_.status -in 'pending', 'manager_approved' -and $_.employee_id -ne $emp })
  Write-Host "   waiting claims of other people: $($open.Count)"
  if ($open.Count -gt 0) { CanApprove $o $tok 'expenses' $open[0].id }
}

Write-Host "`n9) attendance regularization (pending) and overtime (approvable)"
$null = Shape (Call "/organizations/$o/attendance/regularization-requests?status=pending&limit=50" $tok)
$null = Shape (Call "/organizations/$o/attendance/overtime/approvable?status=pending" $tok)

Write-Host "`n10) chat: channels, then the newest direct channel's messages"
$ch = Call "/organizations/$o/chat/channels" $tok
$chrows = Shape $ch
if ($chrows.Count -gt 0) {
  $dm = @($chrows | Where-Object { $_.channel_type -eq 'dm' })[0]
  if (-not $dm) { $dm = $chrows[0] }
  $ms = Call "/organizations/$o/chat/channels/$($dm.id)/messages" $tok
  $mrows = Shape $ms
  if ($mrows.Count -gt 0) {
    $mine = @($mrows | Where-Object { $_.sender_user_id -eq $myUser }).Count
    $distinct = @($mrows | Select-Object -ExpandProperty sender_user_id -Unique).Count
    $noName = @($mrows | Where-Object { -not $_.sender_name }).Count
    $files = @($mrows | Where-Object { $_.message_type -eq 'file' })
    $withAtt = @($files | Where-Object { @($_.attachments).Count -gt 0 }).Count
    Write-Host "   messages: $($mrows.Count)   sent by me (sender_user_id = my user id): $mine   distinct senders: $distinct   without sender_name: $noName"
    Write-Host "   file messages: $($files.Count)   with an attachment record: $withAtt"
  }
}

Write-Host "`n11) engage / tasks / tickets / letters / jobs / recognition / compliance"
foreach ($p in "/engagement/announcements", "/engagement/events", "/engagement/surveys?status=active", "/faqs", "/tasks", "/helpdesk/tickets?limit=5", "/letters/employee/${emp}?limit=5", "/recruitment/internal-jobs", "/engagement/recognition?limit=5", "/engagement/recognition/badges", "/compliance/health", "/employees/summaries") {
  Write-Host "  GET $p"
  $null = Shape (Call "/organizations/$o$p" $tok)
}
Write-Host "`nDone. Nothing was changed. Copy everything above and send it back."
