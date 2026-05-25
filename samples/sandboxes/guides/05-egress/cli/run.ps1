$ErrorActionPreference = 'Stop'

$dir = $PSScriptRoot
while ($dir -and -not (Test-Path (Join-Path $dir '.env'))) {
    $parent = Split-Path $dir -Parent
    if ($parent -eq $dir) { break }
    $dir = $parent
}
if (Test-Path (Join-Path $dir '.env')) {
    Get-Content (Join-Path $dir '.env') | ForEach-Object {
        if ($_ -and -not $_.StartsWith('#') -and $_.Contains('=')) {
            $k,$v = $_.Split('=',2)
            [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
        }
    }
}

$Label = "egress-cli-$([guid]::NewGuid().ToString('N').Substring(0,8))"

Write-Host "==> Creating sandbox (label=$Label)..."
aca sandbox create --labels "name=$Label" | Out-Null
$Id = (aca sandbox list -l "name=$Label" -o json | ConvertFrom-Json)[0].id
Write-Host "    sandbox: $Id"

try {
    Write-Host "==> Baseline: curl example.com (Allow by default)..."
    aca sandbox exec --id $Id -c "curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 8 https://example.com"

    Write-Host "==> Set default Deny + allow *.github.com ..."
    aca sandbox egress set --id $Id --default Deny --host-allow "*.github.com" | Out-Null

    Write-Host "==> example.com should now be blocked..."
    try { aca sandbox exec --id $Id -c "curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 8 https://example.com" }
    catch { Write-Host "    (curl failed = blocked, expected)" }

    Write-Host "==> api.github.com should still work..."
    aca sandbox exec --id $Id -c "curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 8 https://api.github.com"

    Write-Host "==> Current policy:"
    aca sandbox egress show --id $Id
}
finally {
    Write-Host "==> Deleting sandbox $Id..."
    aca sandbox delete --id $Id | Out-Null
}
