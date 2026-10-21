param(
    [string]$GodotExe = 'F:\Software\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [string]$StartAt = '',
    [string[]]$Only = @()
)
$ErrorActionPreference = 'Stop'
$env:STG_TEST_POWERSHELL = (Get-Process -Id $PID).Path
# 当前格式16：统一程序、几何、行为/游戏框架、资产保存及真实编辑器回归。
$testScripts = @(
    'tests/unified16_behavior.gd'
    'tests/unified15_behavior.gd'
    'tests/unified15_behavior_ui.gd'
    'tests/unified14_core.gd'
    'tests/unified14_contract.gd'
    'tests/unified14_preview.gd'
    'tests/bullet_geometry.gd'
    'tests/unified14_behavior.gd'
    'tests/architecture_boundaries.gd'
    'tests/asset_storage.gd'
    'tests/game_flow.gd'
    'tests/responsive_ui.gd'
    'tests/ui_scene_authoring.gd'
    'tests/editor_performance.gd'
    'tests/unified14_ui.gd'
    'tests/workshop_render_matrix.gd'
    'tests/attack_program_build.gd'
    'tests/attack_showcase.gd'
    'tests/attack_showcase_ui.gd'
    'tests/attack_showcase_build.gd'
    'tests/attack_program_editor.gd'
    'tests/ui_scene_editor.gd'
)

if ($Only.Count) {
    if ($StartAt) { throw 'Only 和 StartAt 不能同时指定。' }
    $taskRequested = @($Only | ForEach-Object { $taskItem = $_.Replace('\','/'); if (-not $taskItem.StartsWith('tests/')) { $taskItem = 'tests/' + $taskItem }; if (-not $taskItem.EndsWith('.gd')) { $taskItem += '.gd' }; $taskItem })
    foreach ($taskItem in $taskRequested) { if ($taskItem -notin $testScripts) { throw "未知测试入口：$taskItem" } }
    $testScripts = @($testScripts | Where-Object { $_ -in $taskRequested })
}
if ($StartAt) {
    $taskStartIndex = [Array]::IndexOf($testScripts, $StartAt)
    if ($taskStartIndex -lt 0) { throw "未知测试入口：$StartAt" }
    $testScripts = $testScripts[$taskStartIndex..($testScripts.Count - 1)]
}
foreach ($testScript in $testScripts) {
    # 运行时脚本异常可能让 SceneTree 停在空转状态；限制帧数并要求完成报告。
    if ($testScript -in @('tests/unified15_behavior_ui.gd', 'tests/editor_performance.gd', 'tests/workshop_render_matrix.gd', 'tests/unified14_core.gd', 'tests/unified14_contract.gd', 'tests/unified14_preview.gd', 'tests/unified14_ui.gd', 'tests/attack_showcase.gd', 'tests/attack_showcase_ui.gd')) {
        $taskRendered = $testScript -in @('tests/unified15_behavior_ui.gd', 'tests/workshop_render_matrix.gd', 'tests/unified14_ui.gd', 'tests/attack_showcase_ui.gd')
        $taskName = [IO.Path]::GetFileNameWithoutExtension($testScript)
        $output = & (Join-Path $PSScriptRoot 'tests/run_performance_checks.ps1') -GodotExe ($GodotExe.Replace('_console.exe','.exe')) -Name $taskName -TestScript ('res://' + $testScript) -Rendered:$taskRendered
        $engineExit = $LASTEXITCODE
    } elseif ($testScript -in @('tests/ui_scene_editor.gd', 'tests/attack_program_editor.gd')) {
        $taskLogDirectory = Join-Path $PSScriptRoot 'tests/.test_run_logs'
        New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
        $taskName = [IO.Path]::GetFileNameWithoutExtension($testScript)
        $output = & (Join-Path $PSScriptRoot 'tests/run_editor_checks.ps1') -GodotExe $GodotExe -TestScript $taskName -OutputPath (Join-Path $taskLogDirectory "$taskName.stdout.log") -ErrorPath (Join-Path $taskLogDirectory "$taskName.stderr.log")
        $engineExit = $LASTEXITCODE
    } else {
        $taskLogDirectory = Join-Path $PSScriptRoot 'tests/.test_run_logs'
        New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
        $taskName = [IO.Path]::GetFileNameWithoutExtension($testScript)
        $taskOutputPath = Join-Path $taskLogDirectory ($taskName + '.headless.stdout.log')
        $taskErrorPath = Join-Path $taskLogDirectory ($taskName + '.headless.stderr.log')
        $taskProcess = Start-Process -FilePath ($GodotExe.Replace('_console.exe','.exe')) -WindowStyle Hidden -PassThru -ArgumentList @('--headless','--path', ('"{0}"' -f $PSScriptRoot), '--quit-after', '2000', '--script', $testScript) -RedirectStandardOutput $taskOutputPath -RedirectStandardError $taskErrorPath
        if (-not $taskProcess.WaitForExit(60000)) {
            $taskProcess.Kill($true)
            Write-Output "测试超出60秒：$testScript；日志：$taskOutputPath"
            exit 1
        }
        $taskProcess.Refresh()
        $engineExit = $taskProcess.ExitCode
        $output = @(Get-Content -LiteralPath $taskOutputPath) + @(Get-Content -LiteralPath $taskErrorPath)
    }
    $output | Write-Output
    if ($engineExit -ne 0) {
        Write-Output "测试进程失败：$testScript，退出码 $engineExit"
        exit 1
    }
    if ($output | Select-String -Pattern 'SCRIPT ERROR|ERROR:') {
        Write-Output "测试日志包含错误：$testScript"
        exit 1
    }
    if (-not ($output | Select-String -Pattern 'RESULT: \d+ checks, \d+ failures')) {
        Write-Output "测试未报告完成：$testScript"
        exit 1
    }
}
exit 0
