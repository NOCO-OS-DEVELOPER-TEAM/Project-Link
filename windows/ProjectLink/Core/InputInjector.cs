using System.Runtime.InteropServices;

namespace ProjectLink.Core;

/// <summary>
/// Relative mouse / keyboard / media via Win32 SendInput — lowest practical latency on Windows.
/// </summary>
public static class InputInjector
{
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT
    {
        public int dx, dy;
        public uint mouseData, dwFlags, time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT
    {
        public ushort wVk, wScan;
        public uint dwFlags, time;
        public IntPtr dwExtraInfo;
    }

    const uint INPUT_MOUSE = 0;
    const uint INPUT_KEYBOARD = 1;
    const uint MOUSEEVENTF_MOVE = 0x0001;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    const uint MOUSEEVENTF_WHEEL = 0x0800;
    const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public static void Apply(in InputPacket p, float sensitivity = 1.0f)
    {
        if ((p.Flags & InputFlags.Move) != 0 && (p.Dx != 0 || p.Dy != 0))
        {
            var dx = (int)Math.Round(p.Dx * sensitivity);
            var dy = (int)Math.Round(p.Dy * sensitivity);
            Mouse(dx, dy, MOUSEEVENTF_MOVE);
        }

        if ((p.Flags & InputFlags.LeftDown) != 0) Mouse(0, 0, MOUSEEVENTF_LEFTDOWN);
        if ((p.Flags & InputFlags.LeftUp) != 0) Mouse(0, 0, MOUSEEVENTF_LEFTUP);
        if ((p.Flags & InputFlags.RightDown) != 0) Mouse(0, 0, MOUSEEVENTF_RIGHTDOWN);
        if ((p.Flags & InputFlags.RightUp) != 0) Mouse(0, 0, MOUSEEVENTF_RIGHTUP);
        if ((p.Flags & InputFlags.MiddleDown) != 0) Mouse(0, 0, MOUSEEVENTF_MIDDLEDOWN);
        if ((p.Flags & InputFlags.MiddleUp) != 0) Mouse(0, 0, MOUSEEVENTF_MIDDLEUP);

        if ((p.Flags & InputFlags.DoubleClick) != 0)
        {
            Mouse(0, 0, MOUSEEVENTF_LEFTDOWN);
            Mouse(0, 0, MOUSEEVENTF_LEFTUP);
            Mouse(0, 0, MOUSEEVENTF_LEFTDOWN);
            Mouse(0, 0, MOUSEEVENTF_LEFTUP);
        }

        if ((p.Flags & InputFlags.Wheel) != 0 && p.Wheel != 0)
            MouseWheel(p.Wheel);

        if ((p.Flags & (InputFlags.KeyDown | InputFlags.KeyUp)) != 0 && p.Vk != 0)
        {
            ApplyMods(p.Mods, down: true);
            var up = (p.Flags & InputFlags.KeyUp) != 0;
            Key(p.Vk, up);
            if (up) ApplyMods(p.Mods, down: false);
        }
    }

    public static void Media(string action)
    {
        ushort vk = action switch
        {
            "play_pause" => 0xB3,
            "next" => 0xB0,
            "prev" => 0xB1,
            "stop" => 0xB2,
            "vol_up" => 0xAF,
            "vol_down" => 0xAE,
            "mute" => 0xAD,
            _ => 0
        };
        if (vk == 0) return;
        Key(vk, false);
        Key(vk, true);
    }

    public static void TypeText(string text)
    {
        foreach (var ch in text)
        {
            var inputs = new INPUT[2];
            // Unicode keystroke
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].U.ki = new KEYBDINPUT { wScan = ch, dwFlags = 0x0004 }; // KEYEVENTF_UNICODE
            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].U.ki = new KEYBDINPUT { wScan = ch, dwFlags = 0x0004 | KEYEVENTF_KEYUP };
            SendInput(2, inputs, Marshal.SizeOf<INPUT>());
        }
    }

    static void Mouse(int dx, int dy, uint flags)
    {
        var input = new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion { mi = new MOUSEINPUT { dx = dx, dy = dy, dwFlags = flags } }
        };
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    static void MouseWheel(short delta)
    {
        // Windows expects multiples of WHEEL_DELTA (120); mouseData is treated as signed int
        var input = new INPUT
        {
            type = INPUT_MOUSE,
            U = new InputUnion
            {
                mi = new MOUSEINPUT
                {
                    mouseData = unchecked((uint)(delta * 120)),
                    dwFlags = MOUSEEVENTF_WHEEL
                }
            }
        };
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    static void Key(ushort vk, bool up)
    {
        var input = new INPUT
        {
            type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    dwFlags = up ? KEYEVENTF_KEYUP : 0
                }
            }
        };
        SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
    }

    static void ApplyMods(KeyMods mods, bool down)
    {
        if ((mods & KeyMods.Ctrl) != 0) Key(0x11, !down);
        if ((mods & KeyMods.Shift) != 0) Key(0x10, !down);
        if ((mods & KeyMods.Alt) != 0) Key(0x12, !down);
        if ((mods & KeyMods.Win) != 0) Key(0x5B, !down);
    }
}
