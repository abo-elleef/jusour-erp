' Runs the agent with no console window and restarts it if it ever exits.
' Started at logon by the HKLM Run key and once by the installer.
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Do
  ' Wait for the agent to exit (True), then pause before restarting.
  shell.Run """" & dir & "\SaqrPrintAgent.exe""", 0, True
  WScript.Sleep 5000
Loop
