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

$Name = "mi-demo-$([guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    Write-Host "==> Creating temp sandbox group $Name ..."
    aca sandboxgroup create --name $Name --location $env:ACA_REGION | Out-Null

    Write-Host "==> identity assign --system-assigned ..."
    aca sandboxgroup identity assign --name $Name --system-assigned

    Write-Host "==> identity show:"
    aca sandboxgroup identity show --name $Name

    Write-Host "==> identity remove ..."
    aca sandboxgroup identity remove --name $Name | Out-Null

    Write-Host "==> identity show after remove:"
    try { aca sandboxgroup identity show --name $Name } catch { Write-Host "    (no identity)" }
}
finally {
    Write-Host "==> Deleting temp group $Name ..."
    aca sandboxgroup delete --name $Name 2>$null | Out-Null
}
