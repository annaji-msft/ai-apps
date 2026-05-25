# Files - write/read/stat/list/mkdir/rm inside a sandbox (aca CLI).

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

Write-Host '==> Creating sandbox...'
$createOutput = aca sandbox create --disk ubuntu | Out-String
$match = [regex]::Match($createOutput, '(?m)^Created sandbox:\s*(\S+)')
if (-not $match.Success) { throw 'Could not parse sandbox id' }
$SandboxId = $match.Groups[1].Value
Write-Host "    sandbox: $SandboxId"

$LocalFile = Join-Path $env:TEMP 'aca-sample-hello.txt'

try {
    'Hello from the CLI!' | Set-Content -NoNewline -Path $LocalFile

    Write-Host '==> aca sandbox fs write /tmp/hello.txt'
    aca sandbox fs write --id $SandboxId --path /tmp/hello.txt --file $LocalFile

    Write-Host '==> aca sandbox fs cat /tmp/hello.txt'
    aca sandbox fs cat --id $SandboxId --path /tmp/hello.txt

    Write-Host '==> aca sandbox fs stat /tmp/hello.txt'
    aca sandbox fs stat --id $SandboxId --path /tmp/hello.txt

    Write-Host '==> aca sandbox fs mkdir /tmp/demo-dir'
    aca sandbox fs mkdir --id $SandboxId --path /tmp/demo-dir

    Write-Host '==> aca sandbox fs ls /tmp'
    aca sandbox fs ls --id $SandboxId --path /tmp

    Write-Host '==> aca sandbox fs rm /tmp/hello.txt && /tmp/demo-dir'
    aca sandbox fs rm --id $SandboxId --path /tmp/hello.txt
    aca sandbox fs rm --id $SandboxId --path /tmp/demo-dir --recursive

    Write-Host '==> Done.'
}
finally {
    Write-Host "==> Deleting sandbox $SandboxId..."
    aca sandbox delete --id $SandboxId --yes | Out-Null
    Remove-Item -Force -ErrorAction SilentlyContinue $LocalFile
}
