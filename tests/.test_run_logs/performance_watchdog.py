import ctypes as c,ctypes.wintypes as w,subprocess,time,pathlib,json,sys
class Basic(c.Structure):
 _fields_=[('process_time',c.c_longlong),('job_time',c.c_longlong),('flags',w.DWORD),('min_working',c.c_size_t),('max_working',c.c_size_t),('active',w.DWORD),('affinity',c.c_size_t),('priority',w.DWORD),('scheduling',w.DWORD)]
class IO(c.Structure):
 _fields_=[(x,c.c_ulonglong) for x in ['ro','wo','oo','rb','wb','ob']]
class Limits(c.Structure):
 _fields_=[('basic',Basic),('io',IO),('process_memory',c.c_size_t),('job_memory',c.c_size_t),('peak_process',c.c_size_t),('peak_job',c.c_size_t)]
k=c.WinDLL('kernel32',use_last_error=True)
k.CreateJobObjectW.restype=w.HANDLE;k.SetInformationJobObject.argtypes=[w.HANDLE,c.c_int,c.c_void_p,w.DWORD];k.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE];k.TerminateJobObject.argtypes=[w.HANDLE,w.UINT];k.CloseHandle.argtypes=[w.HANDLE]
j=k.CreateJobObjectW(None,None);limit=Limits();limit.basic.flags=0x2000|0x200;limit.job_memory=2*1024**3
assert k.SetInformationJobObject(j,9,c.byref(limit),c.sizeof(limit)),c.get_last_error()
r=pathlib.Path('F:/Portfolio/STGMaker');name=sys.argv[1];script=sys.argv[2];mode=sys.argv[3] if len(sys.argv)>3 else 'headless'
log=r/'tests/.test_run_logs'/f'{name}.log'
args=[r'F:\Software\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe','--path',str(r),'--script',script]
if mode=='headless':args.append('--headless')
if len(sys.argv)>4:args+=['--']+sys.argv[4:]
start=time.monotonic()
with log.open('w',encoding='utf-8') as f:
 p=subprocess.Popen(args,stdout=f,stderr=subprocess.STDOUT,creationflags=0x08000000)
 assert k.AssignProcessToJobObject(j,int(p._handle)),c.get_last_error()
 try:code=p.wait(timeout=10);status='finished'
 except subprocess.TimeoutExpired:k.TerminateJobObject(j,124);p.wait();code=124;status='timeout'
print(json.dumps({'status':status,'code':code,'seconds':time.monotonic()-start,'memory_limit_bytes':limit.job_memory,'log':str(log)}))
k.CloseHandle(j)

