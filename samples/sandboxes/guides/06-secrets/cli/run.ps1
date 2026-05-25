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

$Name = "demo-cli-$([guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    Write-Host "==> Upsert secret $Name ..."
    aca sandboxgroup secret upsert --name $Name --values "API_KEY=sk-test-123,MODEL=gpt-4"

    Write-Host "==> List secrets in this group:"
    aca sandboxgroup secret list

    Write-Host "==> Update the secret..."
    aca sandboxgroup secret upsert --name $Name --values "API_KEY=sk-updated-456,MODEL=gpt-4o"

    Write-Host "==> Done."
}
finally {
    Write-Host "==> Deleting secret $Name..."
    aca sandboxgroup secret delete --name $Name | Out-Null
}
