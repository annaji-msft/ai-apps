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
$Disk = "committed-cli-$suffix"
$PLabel = "primer-$suffix"
$CLabel = "clone-$suffix"

$Pid2 = $null; $Cid = $null
try {
    Write-Host "==> Primer sandbox..."
    aca sandbox create --labels "name=$PLabel" | Out-Null
    $Pid2 = (aca sandbox list -l "name=$PLabel" -o json | ConvertFrom-Json)[0].id
    aca sandbox exec --id $Pid2 -c "mkdir -p /opt && echo 'baked-at: `$(date)' > /opt/marker.txt"
    Write-Host "    primer wrote /opt/marker.txt"

    Write-Host "==> Committing as disk $Disk (5-10 min)..."
    aca sandbox commit --id $Pid2 --name $Disk

    Write-Host "==> Deleting primer..."
    aca sandbox delete --id $Pid2 | Out-Null
    $Pid2 = $null
    Start-Sleep -Seconds 5

    Write-Host "==> Boot clone sandbox from $Disk ..."
    aca sandbox create --disk $Disk --labels "name=$CLabel" | Out-Null
    $Cid = (aca sandbox list -l "name=$CLabel" -o json | ConvertFrom-Json)[0].id
    Start-Sleep -Seconds 8

    Write-Host "==> Verify /opt/marker.txt survived..."
    aca sandbox exec --id $Cid -c "cat /opt/marker.txt"
}
finally {
    foreach ($id in @($Pid2, $Cid)) {
        if ($id) { aca sandbox delete --id $id 2>$null | Out-Null }
    }
    $disks = aca sandboxgroup disk list -o json | ConvertFrom-Json
    foreach ($d in $disks) {
        if ($d.labels.name -eq $Disk) { aca sandboxgroup disk delete --id $d.id 2>$null | Out-Null }
    }
}
