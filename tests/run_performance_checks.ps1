param(
 [string]$GodotExe = 'F:\Software\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe',
 [string]$Name = 'editor_performance',
 [string]$TestScript = 'res://tests/editor_performance.gd',
 [string[]]$TestArguments = @(),
 [switch]$Rendered,
 [switch]$LaunchWorkshop
)
$ErrorActionPreference = 'Stop'
# Job 对整个子进程树施加 2GB 提交内存硬限，关闭句柄时结束全部子进程。
if (-not ('STGPerformanceJob' -as [type])) {
 Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class STGPerformanceJob {
 [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
 [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] struct Limit { public Basic basic; public IO io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security,string name);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int type,ref Limit value,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll")] public static extern bool TerminateJobObject(IntPtr job,uint code);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr job);
 public static IntPtr Create() {
  var job=CreateJobObject(IntPtr.Zero,null); var value=new Limit();
  value.basic.flags=0x2000|0x200;value.jobMemory=(UIntPtr)2147483648UL;
  if(job==IntPtr.Zero || !SetInformationJobObject(job,9,ref value,(uint)Marshal.SizeOf(value))) throw new Exception("Cannot configure 2GB Job: "+Marshal.GetLastWin32Error());
  return job;
 }
}
"@
}
$taskProject = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$taskLogs = Join-Path $PSScriptRoot '.test_run_logs'
New-Item -ItemType Directory -Path $taskLogs -Force | Out-Null
$taskOutput = Join-Path $taskLogs ($Name + '.stdout.log')
$taskError = Join-Path $taskLogs ($Name + '.stderr.log')
$taskArgs = @('--path', ('"{0}"' -f $taskProject))
if ($LaunchWorkshop) { $taskArgs += @('--quit-after', '120') } else { $taskArgs += @('--script', $TestScript) }
if (-not $Rendered) { $taskArgs += '--headless' }
if ($TestArguments.Count) { $taskArgs += '--'; $taskArgs += $TestArguments }
$taskJob = [STGPerformanceJob]::Create()
$taskClock = [Diagnostics.Stopwatch]::StartNew()
$taskCode = 1
$taskStatus = 'failed'
try {
 $taskProcess = Start-Process -FilePath $GodotExe -WindowStyle Hidden -PassThru -ArgumentList $taskArgs -RedirectStandardOutput $taskOutput -RedirectStandardError $taskError
 if (-not [STGPerformanceJob]::AssignProcessToJobObject($taskJob,$taskProcess.Handle)) {
  $taskProcess.Kill($true)
  throw 'Cannot attach child process to memory-limited Job.'
 }
 $taskRemaining = [Math]::Max(1,10000-[int]$taskClock.ElapsedMilliseconds)
 if (-not $taskProcess.WaitForExit($taskRemaining)) {
  [STGPerformanceJob]::TerminateJobObject($taskJob,124) | Out-Null
  $taskProcess.WaitForExit()
  $taskCode=124; $taskStatus='timeout'
 } else {
  $taskProcess.Refresh();$taskCode=$taskProcess.ExitCode
  $taskStatus=if($taskCode -eq 0){'finished'}else{'failed_or_memory_limit'}
 }
} finally {
 [STGPerformanceJob]::CloseHandle($taskJob) | Out-Null
 $taskClock.Stop()
 @{status=$taskStatus;exit_code=$taskCode;elapsed_ms=$taskClock.ElapsedMilliseconds;memory_limit_bytes=2147483648;timeout_ms=10000} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskLogs ($Name+'.watchdog.json')) -Encoding utf8
}
$taskMessages = @(Get-Content -LiteralPath $taskOutput) + @(Get-Content -LiteralPath $taskError)
$taskMessages | Write-Output
if ($taskCode -ne 0) { exit $taskCode }
if ($taskMessages | Select-String -Pattern 'SCRIPT ERROR|ERROR:') { exit 1 }
if ($LaunchWorkshop) { Write-Output 'WORKSHOP STARTUP RESULT: 1 checks, 0 failures'; exit 0 }
if (-not ($taskMessages | Select-String -Pattern 'RESULT: \d+ checks, 0 failures')) { exit 1 }
exit 0
