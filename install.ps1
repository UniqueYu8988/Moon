$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    throw "Moon currently supports Windows only."
}

$python = (& python -c "import sys; print(sys.executable)").Trim()
if (-not $python) {
    throw "Python 3 was not found. Install it from python.org first."
}

& $python -m pip install -r (Join-Path $PSScriptRoot "requirements.txt")
& (Join-Path $PSScriptRoot "install_windows_moon_task.ps1")
& (Join-Path $PSScriptRoot "install_windows_moon_library_task.ps1")
& (Join-Path $PSScriptRoot "install_windows_display_watcher_task.ps1")
& $python (Join-Path $PSScriptRoot "update_moon_from_nasa.py")

Write-Host "Moon is installed. The wallpaper refreshes every two hours in the background."
