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

$Label = "lc-cli-$([guid]::NewGuid().ToString('N').Substring(0,8))"

aca sandbox create --labels "name=$Label" | Out-Null
$Id = (aca sandbox list -l "name=$Label" -o json | ConvertFrom-Json)[0].id
Write-Host "==> sandbox: $Id"

function Get-State { (aca sandbox get --id $Id -o json | ConvertFrom-Json).state }

try {
    Write-Host "==> state: $(Get-State)"
    Write-Host "==> lifecycle set --auto-suspend 60 ..."
    aca sandbox lifecycle set --id $Id --auto-suspend 60 | Out-Null

    Write-Host "==> stop ..."
    aca sandbox stop --id $Id | Out-Null
    Start-Sleep -Seconds 3
    Write-Host "    state: $(Get-State)"

    Write-Host "==> resume ..."
    aca sandbox resume --id $Id | Out-Null
    Start-Sleep -Seconds 5
    Write-Host "    state: $(Get-State)"

    Write-Host "==> exec uptime ..."
    aca sandbox exec --id $Id -c "uptime"
}
finally {
    aca sandbox delete --id $Id 2>$null | Out-Null
}
