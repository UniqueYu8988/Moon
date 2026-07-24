$taskNames = @(
    "Henan NASA Moon Wallpaper",
    "Henan NASA Moon Offline Library",
    "Moon Display Watcher",
    "Local Moon Clock Widget"
)

foreach ($taskName in $taskNames) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task: $taskName"
    }
}

Write-Host "Moon has been uninstalled. Downloaded images remain in the cache folder and can be deleted manually."
