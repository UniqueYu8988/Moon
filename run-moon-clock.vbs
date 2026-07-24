Option Explicit
Dim shell, fileSystem, root, command, result
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")
root = fileSystem.GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & root & "\moon_clock.ps1"""
result = shell.Run(command, 0, True)
WScript.Quit result
