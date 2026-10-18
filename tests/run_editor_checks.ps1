param(
    [Parameter(Mandatory = $true)][string]$GodotExe,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$ErrorPath,
    [ValidateSet('editor_extensions', 'project_dialogs')][string]$TestScript = 'editor_extensions'
)
$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$taskConfig = Join-Path $taskProject 'project.godot'
$taskProbe = [IO.Path]::GetFullPath((Join-Path $taskProject 'addons/.stg_editor_test'))
if (-not $taskProbe.StartsWith($taskProject.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '测试插件目录越界。' }
if (Test-Path -LiteralPath $taskProbe) { throw '测试插件目录已存在，拒绝覆盖。' }
$taskOriginal = [IO.File]::ReadAllBytes($taskConfig)
$taskText = [Text.Encoding]::UTF8.GetString($taskOriginal)
$taskPattern = [regex]'(?m)^enabled\s*=\s*PackedStringArray\(([^)]*)\)'
$taskMatch = $taskPattern.Match($taskText)
if (-not $taskMatch.Success) { throw '找不到编辑器插件配置。' }
$taskPlugins = $taskMatch.Groups[1].Value.Trim()
$taskEnabled = 'enabled=PackedStringArray(' + $taskPlugins + $(if ($taskPlugins) { ',' } else { '' }) + '"res://addons/.stg_editor_test/plugin.cfg")'
$taskCode = 1
try {
    New-Item -ItemType Directory -Path $taskProbe | Out-Null
    [IO.File]::WriteAllText((Join-Path $taskProbe 'plugin.cfg'), "[plugin]`nname=`"STGMaker Editor Validation`"`ndescription=`"Temporary test probe`"`nauthor=`"STGMaker`"`nversion=`"1`"`nscript=`"plugin.gd`"`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $taskProbe 'plugin.gd'), "@tool`nextends `"res://tests/$TestScript.gd`"`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($taskConfig, $taskText.Replace($taskMatch.Value, $taskEnabled), [Text.UTF8Encoding]::new($false))
    $taskProcess = Start-Process -FilePath $GodotExe -WindowStyle Hidden -PassThru -ArgumentList @('--editor', '--path', ('"{0}"' -f $taskProject), '--quit-after', '2000') -RedirectStandardOutput $OutputPath -RedirectStandardError $ErrorPath
    if (-not $taskProcess.WaitForExit(60000)) { $taskProcess.Kill(); throw '编辑器测试超出 60 秒。' }
    $taskProcess.Refresh()
    $taskCode = $taskProcess.ExitCode
} finally {
    [IO.File]::WriteAllBytes($taskConfig, $taskOriginal)
    # 只移除本次创建的明确文件；不做递归删除。
    foreach ($taskName in @('plugin.cfg', 'plugin.gd', 'plugin.gd.uid')) {
        $taskFile = Join-Path $taskProbe $taskName
        if (Test-Path -LiteralPath $taskFile -PathType Leaf) { Remove-Item -LiteralPath $taskFile }
    }
    if (Test-Path -LiteralPath $taskProbe -PathType Container) { Remove-Item -LiteralPath $taskProbe }
}
Get-Content -LiteralPath $OutputPath,$ErrorPath -Encoding UTF8 | Write-Output
exit $taskCode
