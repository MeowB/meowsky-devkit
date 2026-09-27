# Narrow documented Win32 boundary. Imported without calling native APIs or changing settings.
function Initialize-MeowskyWindowsNative {
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows personalization requires Windows.' }
  if ('Meowsky.Identity.WindowsNative' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Meowsky.Identity {
    public static class WindowsNative {
        [StructLayout(LayoutKind.Sequential)]
        private struct HighContrast { public uint Size; public uint Flags; public IntPtr Scheme; }
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SystemParametersInfoW(uint action, uint size, ref HighContrast value, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeoutW(IntPtr window, uint message, UIntPtr wparam,
            string lparam, uint flags, uint timeout, out UIntPtr result);
        private static HighContrast Read() {
            HighContrast value = new HighContrast();
            value.Size = (uint)Marshal.SizeOf(typeof(HighContrast));
            if (!SystemParametersInfoW(0x42, value.Size, ref value, 0)) throw new Win32Exception();
            return value;
        }
        public static uint GetContrastFlags() {
            // The getter's scheme pointer is borrowed from user32; never free it.
            return Read().Flags;
        }
        public static void DisableContrast() {
            HighContrast value = Read();
            if ((value.Flags & 1) == 0) return;
            string scheme = value.Scheme == IntPtr.Zero ? null : Marshal.PtrToStringUni(value.Scheme);
            // Own the setter's input buffer rather than handing it user32's borrowed pointer.
            IntPtr ownedScheme = scheme == null ? IntPtr.Zero : Marshal.StringToHGlobalUni(scheme);
            value.Scheme = ownedScheme;
            try {
                // Preserve accessibility/hotkey flags and scheme; allow Windows to restore normal rendering.
                value.Flags &= ~1u;
                value.Flags &= ~0x1000u; // HCF_OPTION_NOTHEMECHANGE must not be used when toggling mode.
                if (!SystemParametersInfoW(0x43, value.Size, ref value, 3)) throw new Win32Exception();
            } finally { if (ownedScheme != IntPtr.Zero) Marshal.FreeHGlobal(ownedScheme); }
            if ((GetContrastFlags() & 1) != 0) throw new InvalidOperationException("Windows contrast mode remained active.");
        }
        public static bool Refresh() {
            UIntPtr result;
            // Bounded broadcast: do not hang on an unresponsive app, restart Explorer, or force logout.
            return SendMessageTimeoutW(new IntPtr(0xffff), 0x001a, UIntPtr.Zero,
                "ImmersiveColorSet", 2, 1000, out result) != IntPtr.Zero;
        }
    }
}
'@ -ErrorAction Stop
}

function Get-MeowskyWindowsContrastState {
  Initialize-MeowskyWindowsNative
  $flags = [Meowsky.Identity.WindowsNative]::GetContrastFlags()
  [pscustomobject]@{ Flags = $flags; Enabled = [bool]($flags -band 1) }
}

function Disable-MeowskyWindowsContrast {
  Initialize-MeowskyWindowsNative
  [Meowsky.Identity.WindowsNative]::DisableContrast()
}

function Send-MeowskyWindowsPersonalizationRefresh {
  Initialize-MeowskyWindowsNative
  [Meowsky.Identity.WindowsNative]::Refresh()
}
