Param(
  [string]$ApiId,
  [Parameter(Mandatory=$true)][string]$Token,
  [string]$Email = "admin1@fiapcloudgames.com",
  [int]$TimeoutSec = 120
)

function Get-ApiIdFromLogs {
  try {
    $logs = docker logs localstack --tail 500 2>&1
    $match = $logs | Select-String -Pattern "API ID:\s*(\w+)"
    if ($match) { return $match.Matches[0].Groups[1].Value }

    $match = $logs | Select-String -Pattern "created API .* -> (\w+)"
    if ($match) { return $match.Matches[0].Groups[1].Value }
  } catch {
    return $null
  }

  return $null
}

if (-not $ApiId) {
  Write-Host "API ID not provided, attempting to detect from LocalStack logs..."
  $ApiId = Get-ApiIdFromLogs
}

if (-not $ApiId) {
  Write-Error "API ID not found. Provide -ApiId or ensure LocalStack logs contain 'API ID'."
  exit 2
}

$url = "http://localhost.localstack.cloud:4566/_aws/execute-api/$ApiId/dev/users/api/v1/User/MakeAdmin"
$body = @{ email = $Email } | ConvertTo-Json -Compress

Write-Host "Testing MakeAdmin -> $url"
Write-Host "Email: $Email"

$start = Get-Date
try {
  $resp = Invoke-WebRequest -Uri $url -Method PUT -Headers @{ Authorization = "Bearer $Token" } -Body $body -ContentType "application/json" -TimeoutSec $TimeoutSec -ErrorAction Stop
  $elapsed = ((Get-Date) - $start).TotalSeconds
  Write-Host "HTTP Status: $($resp.StatusCode)"
  Write-Host "Time: ${elapsed}s"
  Write-Host "Body: $($resp.Content)"
  exit 0
} catch {
  $elapsed = ((Get-Date) - $start).TotalSeconds
  Write-Warning "Invoke-WebRequest failed: $($_.Exception.Message) (elapsed ${elapsed}s)"
  exit 3
}
