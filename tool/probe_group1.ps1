# Group 1 live shape check (READ-ONLY). Run it yourself: it asks for the staging test account's
# email and password (hidden), signs in, and issues GET requests only.
# Prints HTTP status and FIELD NAMES - never field values, tokens or the password.
#
# Endpoints marked NEW were added in the local backend branch and are not deployed yet, so on the
# current staging server they are expected to return 404 until that branch is deployed.
$base = 'https://api.hrtoffy.in'

function Call([string]$method, [string]$path, $body, [string]$token) {
  $h = @{ 'Content-Type' = 'application/json' }
  if ($token) { $h['Authorization'] = "Bearer $token" }
  $a = @{ Uri = "$base$path"; Method = $method; Headers = $h; UseBasicParsing = $true }
  if ($body) { $a['Body'] = ($body | ConvertTo-Json -Depth 6) }
  try { $r = Invoke-WebRequest @a; return @{ status = [int]$r.StatusCode; json = ($r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue) } }
  catch {
    $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    return @{ status = $code; json = $null }
  }
}

function Shape($x, [int]$depth = 0) {
  if ($null -eq $x) { return 'null' }
  if ($x -is [System.Array]) { if ($x.Count -eq 0) { return '[] (empty)' }; return "[$($x.Count)] of " + (Shape $x[0] ($depth + 1)) }
  if ($x -is [pscustomobject]) {
    $names = $x.PSObject.Properties.Name
    if ($depth -ge 1) { return '{' + ($names -join ',') + '}' }
    return '{' + (($names | ForEach-Object { $v = $x.$_; if ($v -is [System.Array] -or $v -is [pscustomobject]) { "$_=" + (Shape $v ($depth + 1)) } else { $_ } }) -join ', ') + '}'
  }
  return $x.GetType().Name
}

$email = Read-Host 'Staging test account email'
$sec = Read-Host 'Password (hidden)' -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

$d = Call 'POST' '/auth/discover-tenants' @{ email = $email } $null
$org = @($d.json.organizations)[0]
if (-not $org) { Write-Host 'No organization returned; stopping.'; return }
$l = Call 'POST' '/auth/login' @{ organizationId = $org.id; email = $email; authMethod = 'password'; credentials = @{ password = $pw } } $null
$pw = $null
if ($l.status -ne 200) { Write-Host "Login failed (HTTP $($l.status))."; return }
$tok = $l.json.accessToken
$o = $org.id
Write-Host "Signed in. Organization: $($org.name)`n"

$ru = Call 'GET' '/auth/resolve-user' $null $tok
$emp = $ru.json.data.employeeId
Write-Host ("{0,-62} {1}  {2}" -f 'GET /auth/resolve-user', $ru.status, (Shape $ru.json.data))

$probes = @(
  @('GET', "/organizations/$o/employees/me", ''),
  @('GET', "/organizations/$o/info", ''),
  @('GET', "/organizations/$o/branding", ''),
  @('GET', "/organizations/$o/notifications?limit=5", ''),
  @('GET', "/organizations/$o/engagement/announcements?limit=5", ''),
  @('GET', "/organizations/$o/engagement/events?limit=5", ''),
  @('GET', "/organizations/$o/faqs", ''),
  @('GET', "/organizations/$o/engagement/surveys?status=active&limit=5", ''),
  @('GET', "/organizations/$o/meals/config", ''),
  @('GET', "/organizations/$o/meals/eligibility/$emp", ''),
  @('GET', "/organizations/$o/employees/$emp/nominees", ''),
  @('GET', "/organizations/$o/employees/$emp/documents", ''),
  @('GET', "/organizations/$o/insurance/policies?employeeId=$emp", ''),
  @('GET', "/organizations/$o/engagement/surveys/my-responses", 'NEW'),
  @('GET', "/organizations/$o/payroll/me/sensitive-profile", 'NEW'),
  @('GET', "/organizations/$o/meals/eligibility/me", 'NEW (me / employeeEligible)')
)
foreach ($p in $probes) {
  $r = Call $p[0] $p[1] $null $tok
  $label = ($p[1] -replace [regex]::Escape($o), '<org>' -replace [regex]::Escape("$emp"), '<emp>')
  $shape = if ($r.json) { Shape $r.json } else { '' }
  Write-Host ("{0,-62} {1}  {2}  {3}" -f ("GET " + $label), $r.status, $p[2], $shape)
}
