#!/usr/bin/env python3
"""Run a PowerShell script (from stdin or -f file) on the Windows VM via SSH."""
import sys, os, base64, argparse, paramiko

HOST = os.environ.get("L2_HOST", "176.53.225.183")
USER = os.environ.get("L2_USER", "Administrator")
PASS = os.environ.get("L2_PASS", "")

ap = argparse.ArgumentParser()
ap.add_argument("-f", "--file")
ap.add_argument("-t", "--timeout", type=int, default=120)
ap.add_argument("--cmd", action="store_true", help="run as cmd.exe command instead of PowerShell")
args = ap.parse_args()

script = open(args.file).read() if args.file else sys.stdin.read()

c = paramiko.SSHClient()
c.load_system_host_keys()
if os.environ.get("L2_TRUST_NEW_HOST_KEY") == "1":
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PASS, timeout=30, look_for_keys=False, allow_agent=False)
if args.cmd:
    command = script.strip()
else:
    enc = base64.b64encode(script.encode("utf-16le")).decode()
    command = f"powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {enc}"
stdin, stdout, stderr = c.exec_command(command, timeout=args.timeout)
out = stdout.read().decode("utf-8", "replace")
err = stderr.read().decode("utf-8", "replace")
rc = stdout.channel.recv_exit_status()
sys.stdout.write(out)
if err.strip():
    sys.stdout.write("\n[STDERR]\n" + err)
print(f"\n[exit={rc}]")
c.close()
