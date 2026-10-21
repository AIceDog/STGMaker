$ErrorActionPreference='Stop'
$taskRoot='F:\Portfolio\STGMaker'
$taskConfig=Join-Path $taskRoot 'project.godot'
$taskPlugin=Join-Path $taskRoot 'addons/.stg_window_probe'
if(Test-Path -LiteralPath $taskPlugin){throw 'Probe exists'}
$taskOriginal=[IO.File]::ReadAllBytes($taskConfig)
$taskText=[Text.Encoding]::UTF8.GetString($taskOriginal)
try{
 New-Item -ItemType Directory -Path $taskPlugin|Out-Null
 [IO.File]::WriteAllText((Join-Path $taskPlugin 'plugin.cfg'),"[plugin]`nname=`"Window probe`"`ndescription=`"Diagnostic`"`nauthor=`"STGMaker`"`nversion=`"1`"`nscript=`"plugin.gd`"`n")
 [IO.File]::WriteAllText((Join-Path $taskPlugin 'plugin.gd'),"@tool`nextends `"res://tests/.test_run_logs/window_focus_probe.gd`"`n")
 $taskText=$taskText.Replace('enabled=PackedStringArray("res://addons/stg_maker/plugin.cfg")','enabled=PackedStringArray("res://addons/stg_maker/plugin.cfg","res://addons/.stg_window_probe/plugin.cfg")')
 [IO.File]::WriteAllText($taskConfig,$taskText,[Text.UTF8Encoding]::new($false))
 $taskProcess=Start-Process -FilePath 'F:\Software\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' -WindowStyle Hidden -PassThru -ArgumentList @('--editor','--path',$taskRoot) -RedirectStandardOutput (Join-Path $taskRoot 'tests/.test_run_logs/window_probe.stdout.log') -RedirectStandardError (Join-Path $taskRoot 'tests/.test_run_logs/window_probe.stderr.log')
 if(-not $taskProcess.WaitForExit(210000)){$taskProcess.Kill($true)}
}finally{
 [IO.File]::WriteAllBytes($taskConfig,$taskOriginal)
 foreach($taskName in @('plugin.cfg','plugin.gd','plugin.gd.uid')){ $taskFile=Join-Path $taskPlugin $taskName;if(Test-Path -LiteralPath $taskFile){Remove-Item -LiteralPath $taskFile}}
 if(Test-Path -LiteralPath $taskPlugin){Remove-Item -LiteralPath $taskPlugin}
}
