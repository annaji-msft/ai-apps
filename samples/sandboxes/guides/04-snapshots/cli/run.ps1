# Snapshots - capture state, boot a new sandbox from it (aca CLI).

$ErrorActionPreference = 'Stop'

$dir = $PSScriptRoot
while ($dir -and -not (Test-Path (Join-Path $dir '.env'))) {
    $parent = Split-Path $dir -Parent
    if ($parent -eq $dir) { break }
    $dir = $parent
}
$envFile = Join-Path $dir '.env'
if (-not (Test-Path $envFile)) {
    Write-Error "Could not find samples/.env - run setup/setup.py first?"
    exit 1
}
Get-Content $envFile | ForEach-Object {
    if ($_ -and -not $_.StartsWith('#') -and $_.Contains('=')) {
        $k, $v = $_.Split('=', 2)
        [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
    }
}

$SnapName  = "getting-started-snap-$PID"
$SandboxA  = $null
$SandboxB  = $null
$LocalFile = Join-Path $env:TEMP 'aca-sample-payload.txt'

function Parse-SandboxId([string]$Output) {
    $m = [regex]::Match($Output, '(?m)^Created sandbox:\s*(\S+)')
    if (-not $m.Success) { throw 'Could not parse sandbox id' }
    return $m.Groups[1].Value
}

try {
    Write-Host '==> Creating sandbox A...'
    $SandboxA = Parse-SandboxId ((aca sandbox create --disk ubuntu) -join "`n")
    Write-Host "    A: $SandboxA"

    Write-Host '==> Writing /tmp/payload.txt in sandbox A...'
    'data-before-snapshot' | Set-Content -NoNewline -Path $LocalFile
    aca sandbox fs write --id $SandboxA --path /tmp/payload.txt --file $LocalFile

    Write-Host "==> Creating snapshot '$SnapName'..."
    aca sandbox snapshot --id $SandboxA --name $SnapName
    Start-Sleep -Seconds 5

    Write-Host '==> Creating sandbox B from snapshot...'
    $SandboxB = Parse-SandboxId ((aca sandbox create --snapshot $SnapName) -join "`n")
    Write-Host "    B: $SandboxB"
    Start-Sleep -Seconds 15

    Write-Host '==> Reading /tmp/payload.txt in sandbox B...'
    aca sandbox fs cat --id $SandboxB --path /tmp/payload.txt
    Write-Host ''

    Write-Host '==> Done.'
}
finally {
    foreach ($id in @($SandboxB, $SandboxA)) {
        if ($id) {
            Write-Host "==> Deleting sandbox $id..."
            aca sandbox delete --id $id --yes 2>$null | Out-Null
        }
    }
    Write-Host "==> Deleting snapshot $SnapName..."
    aca sandboxgroup snapshot delete --selector "name=$SnapName" 2>$null | Out-Null
    Remove-Item -Force -ErrorAction SilentlyContinue $LocalFile
}
