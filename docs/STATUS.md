# L2 C2 Server — Current State & Progress Log

## Date: 2026-10-13

## Environment

- **VM**: Selectel cloud, Windows Server 2019 Standard
  - Public IP: 136.234.76.201, Internal IP: 192.168.0.3
  - Hostname: imani
- **SQL Server**: 2019 Express, SQLEXPRESS, port 1433, mixed mode auth
- **DB login**: gamma (SQL auth, db_owner on all 7 databases)
- **L2 server**: C:\L2Server\ (extracted from RAR, 7605 files)
- **AutoIt**: C:\Program Files (x86)\AutoIt3\AutoIt3.exe
- **PsTools**: C:\pstools\
- **.NET 32-bit compiler**: C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe

## Completed Steps

### 1. Archive Extraction
- RAR archive transferred to VM and extracted to C:\L2Server\

### 2. SQL Server Setup
- SQL Server 2019 Express installed
- TCP/IP enabled on port 1433
- Mixed mode authentication enabled
- SA password set
- SQL Agent stopped (not? needed)

### 3. Database Creation
- 7 databases created: lin2db, lin2world, lin2comm, lin2log, lin2report, lin2user, petition
- SQL auth login `gamma` created, mapped as db_owner on all databases
- All schemas imported from the archive's SQL files

### 4. ODBC Configuration
- System DSNs created in 32-bit registry (WOW6432Node) for all database names
- Two drivers in use:
  - `sqlsrv32.dll` (SQL Server) for: l2logd, l2cache, l2server, l2npc, L2AUTHD, etc.
  - `msodbcsql17.dll` (ODBC Driver 17) for: lin2db, lin2world, lin2log, etc.
- File DSNs created with absolute paths for each service
- ODBC File DSN path set to C:\Program Files (x86)\Common Files\ODBC\Data Sources

### 5. INI Configuration
- All .ini files configured:
  - IPs"IPs to 127.0.0.1 (local)
  - DevServerIP to public IP (136.234.76.201)
  - Ports: L2LogD=3999, CacheD=2006/2008, L2Server=7777, L2AuthD!7777, AuthD=2106
- L2LOG.INI created as copy of l2logd.ini
- INI files also copied to C:\Windows\ for GetPrivateProfileString default path

### 6. Registry Configuration
- HKLM\SOFTWARE\WOW6432Node\PROJECT_L2\L2LOGD — DSN, UID, PWD, FILEDSN, connStr, connStrBBS, DBConn
- HKLM\SOFTWARE\WOW6432Node\PROJECT_L2\L2CACHED — DSN, UID, PWD, FILEDSN, connStr
- HKLM\SOFTWARE\WOW6432Node\PROJECT_L2\L2SERVER — DSN, UID, PWD, posx/posy/sizex/sizey
- HKLM\SOFTWARE\WOW6432Node\PROJECT_L2\L2NPC — DSN, UID, PWD, posx/posy/sizex/sizey
- HKLM\SOFTWARE\WOW6432Node\NCSoft\L2AUTHD\L2Conn — FILEDSN, UID, PWD, etc.

### 7. Windows Configuration
- DEP completely disabled (bcdedit /set nx AlwaysOff)
- Windows Firewall rules for ports 2104, 7777, 2106
- RDP enabled on port 3389

### 8. L2AuthD Configuration
- encrypt = false (in config.txt)
- DevServerIP = false (prevented strlen(NULL) crash)
- serverexport = public IP

## Current Blocker

### L2LogD Login Dialog

L2LogD shows a modal "LogDB Login" dialog on startup. The dialog has:
- File DSN field (ID 1000) — hardcoded default "linworld"
- Login Name field (ID 1001) — empty
- Password field (ID 1002) — empty
- OK button (ID 1), CANCEL button (ID 7)

**Root cause analysis:**

1. The string "linworld" is hardcoded in L2LogD.exe at Unicode offset 0x12216
2. "linworld" is a relative path — FILEDSN=linworld fails because the old
   SQL Server ODBC driver (sqlsrv32.dll) cannot resolve relative File DSN paths
3. The error is: SQLState=HY000, Native=556, "General error: Invalid file dsn ''"
4. Absolute paths work: FILEDSN=C:\L2Server\L2LogD\l2logd.dsn succeeds

**Dialog interaction attempts:**

- ControlSetText: appears to set text (ControlGetText confirms), but after
  clicking OK the dialog recreates with default values
- The dialog HWND changes after OK click (closes and reopens)
- This does NOT prove the OK handler read the default — it may have read
  the set value, tried to connect, and failed for a different reason
- ODBC trace shows SQLDriverConnectW returns SQL_ERROR with no diagnostic records

**connStr registry value:**
- Original: REG_BINARY, 256 bytes
- String part: FILEDSN=linworld;UID=;PWD= (Unicode, 52 bytes)
- Binary part: 204 bytes (C++ object state, format unknown)
- Modifications to connStr did not change dialog default (linworld is hardcoded in EXE)

## What Works

- ODBC connection from 32-bit process with absolute File DSN path: SUCCESS
- All 7 databases accessible with gamma login
- SQL Server listening on port 1433
- L2AuthD starts without crash (encrypt=false, DevServerIP=false)
- Registry auditing confirms L2LogD reads PROJECT_L2\L2LOGD key

## What Doesn't Work

- FILEDSN=linworld (relative path) — driver can't resolve
- ControlSetText across processes — may not update edit control internal buffer
- SendMessage WM_SETTEXT across processes — hangs
- CreateRemoteThread — hangs (possibly due to 64-bit/32-bit mismatch in earlier attempts)
- ProcMon — driver doesn't load, PML file is 0 bytes

## Next Steps

1. Controlled L2LogD launch with ODBC tracing
2. Set absolute DSN path + credentials, verify by reading back
3. Click OK, capture ODBC trace (return code, SQLSTATE)
4. Determine if the service reads the set values or the hardcoded defaults
5. If automation fails, manual RDP session to fill dialog by hand
6. Once L2LogD starts, proceed with CacheD, L2Server, L2NPC, PetitionD
