' Starts the agent with no console window. Used by the logon task.
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run """" & dir & "\SaqrPrintAgent.exe""", 0, False
