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
$Vol = "vol-cli-$suffix"
$PLabel = "vol-prod-$suffix"
$CLabel = "vol-cons-$suffix"

Write-Host "==> Creating AzureBlob volume $Vol ..."
aca sandboxgroup volume create --name $Vol --type AzureBlob | Out-Null

$Pid2 = $null; $Cid = $null
try {
    Write-Host "==> Producer sandbox..."
    aca sandbox create --labels "name=$PLabel" | Out-Null
    $Pid2 = (aca sandbox list -l "name=$PLabel" -o json | ConvertFrom-Json)[0].id
    aca sandbox mount --id $Pid2 --volume $Vol --path /mnt/shared | Out-Null
    aca sandbox exec --id $Pid2 -c "echo '{\""answer\"":42,\""status\"":\""ok\""}' > /mnt/shared/output.json"
    Write-Host "    producer wrote /mnt/shared/output.json"

    Write-Host "==> Consumer sandbox..."
    aca sandbox create --labels "name=$CLabel" | Out-Null
    $Cid = (aca sandbox list -l "name=$CLabel" -o json | ConvertFrom-Json)[0].id
    aca sandbox mount --id $Cid --volume $Vol --path /mnt/shared | Out-Null
    Write-Host "==> Consumer reads:"
    aca sandbox exec --id $Cid -c "cat /mnt/shared/output.json"
}
finally {
    foreach ($id in @($Pid2, $Cid)) {
        if ($id) { aca sandbox delete --id $id 2>$null | Out-Null }
    }
    aca sandboxgroup volume delete --name $Vol 2>$null | Out-Null
}
