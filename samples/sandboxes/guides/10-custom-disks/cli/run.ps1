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

$suffix = [guid]::NewGuid().ToString('N').Substring(0,8)
$Disk = "alpine-cli-$suffix"
$SLabel = "cdisk-cli-$suffix"

$Sid = $null; $Did = $null
try {
    Write-Host "==> Building disk image $Disk from alpine:3.19 (5-10 min)..."
    aca sandboxgroup disk create --image docker.io/library/alpine:3.19 --name $Disk

    Write-Host "==> Listing disks:"
    aca sandboxgroup disk list

    Write-Host "==> Boot sandbox from $Disk ..."
    aca sandbox create --disk $Disk --labels "name=$SLabel" | Out-Null
    $Sid = (aca sandbox list -l "name=$SLabel" -o json | ConvertFrom-Json)[0].id
    Write-Host "    sandbox: $Sid"

    Write-Host "==> cat /etc/alpine-release ..."
    aca sandbox exec --id $Sid -c "cat /etc/alpine-release"
}
finally {
    if ($Sid) { aca sandbox delete --id $Sid 2>$null | Out-Null }
    $disks = aca sandboxgroup disk list -o json | ConvertFrom-Json
    foreach ($d in $disks) {
        if ($d.labels.name -eq $Disk) { aca sandboxgroup disk delete --id $d.id 2>$null | Out-Null }
    }
}
