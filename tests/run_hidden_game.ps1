param(
    [Parameter(Mandatory = $true)][string]$Engine,
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Script = '',
    [int]$Frames = 30
)
$ErrorActionPreference = 'Stop'
# 与玩家实际运行相同的 Windows/OpenGL 后端；隐藏窗口，保留原始退出码和错误日志。
$taskOutput = Join-Path $Project '.runtime_validation.stdout.log'
$taskError = Join-Path $Project '.runtime_validation.stderr.log'
$taskArguments = @('--path', ('"{0}"' -f $Project), '--quit-after', $Frames)
if (-not [string]::IsNullOrEmpty($Script)) { $taskArguments += @('--script', ('"{0}"' -f $Script)) }
$taskProcess = Start-Process -FilePath $Engine -WindowStyle Hidden -PassThru -ArgumentList $taskArguments -RedirectStandardOutput $taskOutput -RedirectStandardError $taskError
if (-not $taskProcess.WaitForExit(60000)) {
    $taskProcess.Kill()
    Write-Output 'ERROR: Game validation exceeded 60 seconds.'
    exit 1
}
$taskProcess.Refresh()
Get-Content -LiteralPath $taskOutput,$taskError -Encoding UTF8 | Write-Output
exit $taskProcess.ExitCode
