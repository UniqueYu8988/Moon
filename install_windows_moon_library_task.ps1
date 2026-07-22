$taskName = "Henan NASA Moon Offline Library"
$script = Join-Path $PSScriptRoot "prefetch_nasa_moon_year.py"
$python = (& python -c "import sys; print(sys.executable)").Trim()
$pythonw = Join-Path (Split-Path $python) "pythonw.exe"
if (-not (Test-Path -LiteralPath $pythonw)) {
    throw "pythonw.exe was not found next to $python. Install Python from python.org and try again."
}

$action = New-ScheduledTaskAction -Execute $pythonw -Argument ('"' + $script + '" --workers 6') -WorkingDirectory $PSScriptRoot
$daily = New-ScheduledTaskTrigger -Daily -At "03:30"
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$logon.Delay = "PT10M"
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 12)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

$task = New-ScheduledTask -Action $action -Trigger @($daily, $logon) -Settings $settings -Principal $principal -Description "Caches NASA daily 4K Moon frames with resume support and discovers the next annual dataset after November."
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State
