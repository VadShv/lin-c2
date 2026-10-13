#!/usr/bin/env python3
"""Send a PowerShell snippet to the supervisor queue on the VM and print its output."""
import sys, os, time, paramiko
HOST=os.environ.get("L2_HOST","176.53.225.183"); USER=os.environ.get("L2_USER","Administrator"); PASS=os.environ.get("L2_PASS","")
script = open(sys.argv[1]).read() if len(sys.argv)>1 and sys.argv[1]!='-' else sys.stdin.read()
timeout = int(os.environ.get("L2_TIMEOUT","180"))
c=paramiko.SSHClient(); c.load_system_host_keys()
if os.environ.get("L2_TRUST_NEW_HOST_KEY") == "1":
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST,username=USER,password=PASS,look_for_keys=False,allow_agent=False,timeout=30)
s=c.open_sftp()
name=f"c{int(time.time()*1000)}"
with s.open(f"C:/l2work/cmd/{name}.tmp","w") as f: f.write(script)
s.rename(f"C:/l2work/cmd/{name}.tmp", f"C:/l2work/cmd/{name}.ps1")
deadline=time.time()+timeout; outp=f"C:/l2work/out/{name}.txt"
while time.time()<deadline:
    try:
        with s.open(outp,"r") as f: data=f.read().decode("utf-8","replace")
        print(data.lstrip("\ufeff")); break
    except IOError: time.sleep(1.5)
else:
    print(f"[timeout waiting for supervisor output {name}; queued script may still run]")
    s.close(); c.close(); sys.exit(1)
s.close(); c.close()
