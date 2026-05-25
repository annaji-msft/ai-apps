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

$Tenant = "t-$([guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    for ($i=0; $i -lt 3; $i++) {
        $role = if ($i -lt 2) { 'worker' } else { 'control' }
        $name = "sbx-$Tenant-$i"
        Write-Host "==> Create $name (role=$role)..."
        aca sandbox create --labels "name=$name,tenant=$Tenant,role=$role" | Out-Null
    }

    Write-Host ""
    Write-Host "==> Workers under tenant=$Tenant"
    aca sandbox list -l "tenant=$Tenant,role=worker"
    Write-Host ""
    Write-Host "==> Control under tenant=$Tenant"
    aca sandbox list -l "tenant=$Tenant,role=control"
}
finally {
    $ids = (aca sandbox list -l "tenant=$Tenant" -o json | ConvertFrom-Json) | ForEach-Object { $_.id }
    foreach ($id in $ids) { aca sandbox delete --id $id 2>$null | Out-Null }
}
