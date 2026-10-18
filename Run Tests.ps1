param(
    [string]$GodotExe = 'F:\Software\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [string]$StartAt = ''
)
$ErrorActionPreference = 'Stop'
$env:STG_TEST_POWERSHELL = (Get-Process -Id $PID).Path
# 按“战斗规则 → 编辑交互 → 关卡与资产”的顺序定位失败模块。
$testScripts = @(
    'tests/smoke.gd'
    'tests/behavior_flow.gd'
    'tests/trail_interaction.gd'
    'tests/authoring.gd'
    'tests/draft_safety.gd'
    'tests/planner_diagnostics.gd'
    'tests/flow_editor.gd'
    'tests/responsive_ui.gd'
    'tests/planner_ui.gd'
    'tests/interaction_ui.gd'
    'tests/ui_help.gd'
    'tests/control_help_catalog.gd'
    'tests/workspace_navigation.gd'
    'tests/emission_motion.gd'
    'tests/authoring_boundary_ui.gd'
    'tests/bullet_geometry.gd'
    'tests/attack_lifecycle.gd'
    'tests/authoring_design.gd'
    'tests/projectile_presentation.gd'
    'tests/trajectory_preview.gd'
    'tests/enemy_examples.gd'
    'tests/horizontal_preview.gd'
    'tests/level_runtime.gd'
    'tests/level_editor.gd'
    'tests/level_conditions.gd'
    'tests/level_timeline.gd'
    'tests/timeline_efficiency.gd'
    'tests/timeline_demo.gd'
    'tests/flytiger_physics.gd'
    'tests/flytiger_templates.gd'
    'tests/flytiger_bosses.gd'
    'tests/extensions.gd'
    'tests/extension_protocol.gd'
    'tests/current_architecture.gd'
    'tests/asset_storage.gd'
    'tests/architecture_boundaries.gd'
    'tests/extension_authoring.gd'
    'tests/editor_extensions.gd'
    'tests/project_dialogs.gd'
    'tests/game_flow.gd'
    'tests/first_game_content.gd'
    'tests/game_project_ui.gd'
    'tests/game_build.gd'
    'tests/modular_build.gd'
)

if ($StartAt) {
    $taskStartIndex = [Array]::IndexOf($testScripts, $StartAt)
    if ($taskStartIndex -lt 0) { throw "未知测试入口：$StartAt" }
    $testScripts = $testScripts[$taskStartIndex..($testScripts.Count - 1)]
}
foreach ($testScript in $testScripts) {
    # 运行时脚本异常可能让 SceneTree 停在空转状态；限制帧数并要求完成报告。
    if ($testScript -in @('tests/editor_extensions.gd', 'tests/project_dialogs.gd')) {
        $taskLogDirectory = Join-Path $PSScriptRoot 'tests/.test_run_logs'
        New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
        $taskName = [IO.Path]::GetFileNameWithoutExtension($testScript)
        $output = & (Join-Path $PSScriptRoot 'tests/run_editor_checks.ps1') -GodotExe $GodotExe -TestScript $taskName -OutputPath (Join-Path $taskLogDirectory "$taskName.stdout.log") -ErrorPath (Join-Path $taskLogDirectory "$taskName.stderr.log")
        $engineExit = $LASTEXITCODE
    } elseif ($testScript -in @('tests/game_project_ui.gd', 'tests/draft_safety.gd', 'tests/timeline_efficiency.gd', 'tests/extension_authoring.gd', 'tests/authoring_boundary_ui.gd', 'tests/horizontal_preview.gd')) {
        # 原生子窗口 / Tree 控件的 UI 验收使用实际渲染器，覆盖用户真实使用的后端。
        # Dummy 后端曾在完成断言后原生崩溃；非零退出仍视为失败，不重试吞错。
        # 隐藏启动，保留全部控件断言、日志和非零退出检查，不以重试掩盖失败。
        $taskLogDirectory = Join-Path $PSScriptRoot 'tests/.test_run_logs'
        New-Item -ItemType Directory -Path $taskLogDirectory -Force | Out-Null
        $taskOutputPath = Join-Path $taskLogDirectory ([IO.Path]::GetFileNameWithoutExtension($testScript) + '.stdout.log')
        $taskErrorPath = Join-Path $taskLogDirectory ([IO.Path]::GetFileNameWithoutExtension($testScript) + '.stderr.log')
        $taskProcess = Start-Process -FilePath $GodotExe -WindowStyle Hidden -PassThru `
            -ArgumentList @('--path', ('"{0}"' -f $PSScriptRoot), '--quit-after', '2000', '--script', $testScript) `
            -RedirectStandardOutput $taskOutputPath -RedirectStandardError $taskErrorPath
        $taskProcess.WaitForExit()
        $engineExit = $taskProcess.ExitCode
        $output = @(Get-Content -LiteralPath $taskOutputPath) + @(Get-Content -LiteralPath $taskErrorPath)
    } else {
        $output = & $GodotExe --headless --path $PSScriptRoot --quit-after 2000 --script $testScript 2>&1
        $engineExit = $LASTEXITCODE
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
