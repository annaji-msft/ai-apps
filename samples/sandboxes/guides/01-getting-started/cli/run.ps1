# Getting started - create a sandbox, run a command, delete it (aca CLI).
#
# Reads samples/.env (written by samples/sandboxes/setup/setup.py) for
# ACA_SUBSCRIPTION, ACA_RESOURCE_GROUP, ACA_SANDBOX_GROUP.

$ErrorActionPreference = 'Stop'

# Walk up from this script to find samples/.env.
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

Write-Host '==> Creating sandbox...'
$createOutput = aca sandbox create --disk ubuntu | Out-String
Write-Host $createOutput.TrimEnd()
$match = [regex]::Match($createOutput, '(?m)^Created sandbox:\s*(\S+)')
if (-not $match.Success) {
    throw 'Could not parse sandbox id from create output'
}
$SandboxId = $match.Groups[1].Value

try {
    Write-Host '==> Running command in sandbox...'
    aca sandbox exec --id $SandboxId -c 'echo hello world && uname -a'
}
finally {
    Write-Host "==> Deleting sandbox $SandboxId..."
    aca sandbox delete --id $SandboxId --yes | Out-Null
}

Write-Host '==> Done.'
