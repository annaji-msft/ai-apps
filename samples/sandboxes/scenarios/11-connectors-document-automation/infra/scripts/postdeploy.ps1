# Thin wrapper — installs the Python deps the orchestration script
# needs into a local venv and runs it.

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Venv = Join-Path $Here ".venv"
$Activate = Join-Path $Venv "Scripts\Activate.ps1"

if (-not (Test-Path $Activate)) {
    Write-Host "==> creating postdeploy venv at $Venv"
    python -m venv $Venv
}
& $Activate
python -m pip install --quiet --upgrade pip
python -m pip install --quiet `
    azure-identity `
    'azure-containerapps-sandbox==0.1.0b1'

python (Join-Path $Here "postdeploy.py") @Args
exit $LASTEXITCODE
