# Lineage 2 Chronicle 2 — Official C++ Server Setup

## Overview

Setup configuration for an official NCSoft Lineage 2 Chronicle 2 (C2) server
(original C++ build, not L2J) running on a Windows Server 2019 VM with SQL Server 2019 Express.

## VM Configuration

- **OS**: Windows Server 2019 Standard, 64-bit
- **Resources**: 2 vCPU, 4 GB RAM, ~33 GB disk
- **SQL Server**: 2019 Express, instance `SQLEXPRESS`, TCP port 1433, mixed mode auth
- **DEP**: Disabled system-wide (`bcdedit /set nx AlwaysOff`)
- **AutoIt**: Installed at `C:\Program Files (x86)\AutoIt3\AutoIt3.exe`
- **PsTools**: Installed at `C:\pstools\`

## Databases

7 databases created with SQL auth login `gamma` (db_owner on all):

| Database   | Used by          |
|------------|------------------|
| lin2db     | L2AuthD          |
| lin2world  | CacheD, L2Server |
| lin2comm   | CacheD           |
| lin2log    | L2LogD           |
| lin2report | L2LogD (BBS)     |
| lin2user   | CacheD           |
| petition   | PetitionD        |

## Service Start Order

```
L2AuthD → CacheD → L2LogD → L2Server → L2NPC → PetitionD
```

All executables are **32-bit x86 GUI applications** (PE subsystem 2).

## What's Done

- [x] RAR archive extracted to `C:\L2Server\` (7605 files)
- [x] SQL Server 2019 Express installed, TCP/IP enabled on port 1433
- [x] 7 databases created with schemas imported
- [x] All `.ini` files configured (IPs to `127.0.0.1`, `DevServerIP` to public IP)
- [x] Windows Firewall rules for ports 2104, 7777, 2106
- [x] ODBC DSNs created (32-bit and 64-bit) for all database names
- [x] File DSNs (`.dsn`) created for all services with absolute paths
- [x] DEP disabled, VM rebooted
- [x] Registry configured for all services (`PROJECT_L2\*`, `NCSoft\L2AUTHD`)
- [x] L2AuthD configured (`encrypt=false`, `DevServerIP=false`)

## Current Blocker: L2LogD Login Dialog

### Problem

L2LogD shows a modal ODBC login dialog (`LogDB Login`, class `#32770`) on startup.
The dialog has three fields:
- **File DSN** (control ID 1000) — default value `linworld` (hardcoded in EXE)
- **Login Name** (control ID 1001) — empty
- **Password** (control ID 1002) — empty

When `ControlSetText` sets the DSN to an absolute path (e.g. `C:\L2Server\L2LogD\l2logd.dsn`)
and `ControlClick` clicks OK, the dialog HWND changes — meaning the dialog closes
and a new one appears. This **does not prove** the OK handler read `linworld`
instead of the set value; the dialog may simply recreate with hardcoded defaults.

### What's Confirmed

1. **ODBC connection works** from a 32-bit process with the same File DSN:
   ```
   FILEDSN=C:\L2Server\L2LogD\l2logd.dsn;UID=gamma;PWD=***;
   → SUCCESS, connects to lin2log
   ```

2. **`FILEDSN=linworld` (relative path) fails** with `SQLState=HY000 Native=556
   Msg=General error: Invalid file dsn ''` — the old `sqlsrv32.dll` driver
   cannot resolve relative File DSN paths.

3. **L2LogD reads the registry** key `HKLM\SOFTWARE\WOW6432Node\PROJECT_L2\L2LOGD`
   (confirmed via Windows registry auditing, event ID 4663).

4. **`connStr` registry value** is `REG_BINARY` (256 bytes):
   - Bytes 0–51: Unicode string `FILEDSN=linworld;UID=;PWD=\0`
   - Bytes 52–255: 204 bytes of binary data (likely C++ object state)

5. **Changing `connStr`** to use an absolute path did NOT change the dialog's
   default DSN value — `linworld` is hardcoded in the executable at Unicode
   offset `0x12216`.

6. **ODBC trace** shows L2LogD calls `SQLDriverConnectW` with
   `SQL_DRIVER_NOPROMPT`, returns `SQL_ERROR`, and `SQLGetDiagRecW`
   returns `SQL_NO_DATA_FOUND` (no error diagnostic records).

### What's Not Yet Determined

- Whether `ControlSetText` actually updates the edit control's internal buffer
  (cross-process `WM_SETTEXT` may set window text property without updating
  the buffer the OK handler reads).
- What exact connection string L2LogD passes to `SQLDriverConnectW`
  (ODBC tracer masks it as `******`).
- Whether the service reads `connStr` from the registry for the initial
  connection attempt before showing the dialog.

### Next Steps

1. Run one controlled L2LogD launch with ODBC tracing.
2. Set absolute DSN path + credentials in dialog, verify by reading back.
3. Click OK once, capture ODBC trace result (return code, SQLSTATE).
4. If the connection string is wrong, investigate why the OK handler
   doesn't read the set values.
5. If automation cannot resolve this, a manual RDP session may be needed
   to fill the dialog by hand.

## File Layout

```
configs/
  dsn/          — File DSN files (*.dsn) for each service
  ini/          — INI configuration files
  other/        — config.txt, run.bat, etc.
registry/       — Registry exports (.reg)
  project_l2.reg — HKLM\SOFTWARE\WOW6432Node\PROJECT_L2
  odbc_ini.reg   — HKLM\SOFTWARE\WOW6432Node\ODBC\ODBC.INI
  ncsoft.reg     — HKLM\SOFTWARE\WOW6432Node\NCSoft
scripts/        — Setup and automation scripts
docs/           — Documentation
```

## Security Note

Database credentials and VM access details are NOT stored in this repository.
They must be provided separately during deployment.
