Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hp, EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetProcessWindowStation();
  [DllImport("user32.dll")] public static extern IntPtr GetThreadDesktop(uint tid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetUserObjectInformation(IntPtr h, int idx, StringBuilder s, int n, out int need);
  public static List<IntPtr> Tops(uint pid){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid) r.Add(h); return true;}, IntPtr.Zero); return r; }
  public static List<IntPtr> Children(IntPtr hp){ var r=new List<IntPtr>(); EnumChildWindows(hp,(h,l)=>{ r.Add(h); return true;}, IntPtr.Zero); return r; }
  public static string Cls(IntPtr h){ var s=new StringBuilder(256); GetClassName(h,s,256); return s.ToString(); }
  public static string Txt(IntPtr h){ var s=new StringBuilder(1024); SendMessage(h,0x000D,(IntPtr)1024,s); return s.ToString(); }
  public static string Station(){ var s=new StringBuilder(256); int n; GetUserObjectInformation(GetProcessWindowStation(),2,s,256,out n); var d=new StringBuilder(256); GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId()),2,d,256,out n); return s+"\\"+d; }
}
"@
function Show-ProcWindows($name) {
  $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
  if (-not $procs) { "  [$name] not running"; return }
  foreach ($p in $procs) {
    "  [$name] PID=$($p.Id) session=$($p.SessionId) threads=$($p.Threads.Count) mem=$([math]::Round($p.WorkingSet64/1MB))MB"
    foreach ($h in [W]::Tops([uint32]$p.Id)) {
      "    TOP 0x{0:X} class='{1}' text='{2}' visible={3}" -f $h.ToInt64(), [W]::Cls($h), [W]::Txt($h), [W]::IsWindowVisible($h)
      foreach ($c in [W]::Children($h)) {
        $id = [W]::GetDlgCtrlID($c)
        $text = if ($id -eq 1002) { '[credential field redacted]' } else { [W]::Txt($c) }
        "       child 0x{0:X} id={1} class='{2}' text='{3}'" -f $c.ToInt64(), $id, [W]::Cls($c), $text
      }
    }
  }
}
