// Sends a slash command only to this tab's console input, never global SendKeys.
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.IO;

public static class CodexStatusConsole
{
    [StructLayout(LayoutKind.Sequential)] struct Coord { public short X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public short Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct BufferInfo {
        public Coord Size, Cursor; public short Attributes; public Rect Window; public Coord Maximum;
    }
    [StructLayout(LayoutKind.Explicit, Size=20)] struct InputRecord {
        [FieldOffset(0)] public short Type;
        [FieldOffset(4)] public int Down;
        [FieldOffset(8)] public short Repeat;
        [FieldOffset(10)] public short Key;
        [FieldOffset(14)] public char Character;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll")] static extern bool GetConsoleScreenBufferInfo(IntPtr handle, out BufferInfo info);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool ReadConsoleOutputCharacterW(IntPtr handle, StringBuilder text, uint size, Coord start, out uint read);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool WriteConsoleInputW(IntPtr handle, InputRecord[] input, uint size, out uint written);
    static Thread worker;
    static volatile bool stop;

    public static bool IsReady(string screen) {
        // Footer text varies: warning counts / f2 replace "for shortcuts".
        if (screen.IndexOf("Trust this folder?", StringComparison.OrdinalIgnoreCase) >= 0
            || screen.IndexOf("Trust and continue", StringComparison.OrdinalIgnoreCase) >= 0
            || screen.IndexOf("Forking session", StringComparison.OrdinalIgnoreCase) >= 0
            || screen.IndexOf("Resuming session", StringComparison.OrdinalIgnoreCase) >= 0)
            return false;
        return screen.IndexOf("Ask Codex", StringComparison.OrdinalIgnoreCase) >= 0
            || (screen.IndexOf('\u203a') >= 0
                && screen.IndexOf("for shortcuts", StringComparison.OrdinalIgnoreCase) >= 0);
    }

    public static bool IsStatusVisible(string screen) {
        return screen.IndexOf("Account:", StringComparison.OrdinalIgnoreCase) >= 0
            && (screen.IndexOf("limit:", StringComparison.OrdinalIgnoreCase) >= 0
                || screen.IndexOf("Session:", StringComparison.OrdinalIgnoreCase) >= 0);
    }

    static void Trace(string path, string text) {
        if (!String.IsNullOrEmpty(path)) {
            try { File.WriteAllText(path, text); } catch {} // Diagnostics must not break the TUI.
        }
    }
    static bool Send(string command) {
        var input = new InputRecord[command.Length * 2];
        for (int i=0; i<command.Length; i++) {
            input[2*i] = new InputRecord { Type=1, Down=1, Repeat=1,
                Key=(short)(command[i]=='\r' ? 13 : 0), Character=command[i] };
            input[2*i+1] = input[2*i]; input[2*i+1].Down=0;
        }
        uint written;
        return WriteConsoleInputW(GetStdHandle(-10), input, (uint)input.Length, out written)
            && written == input.Length;
    }
    public static void Start(int timeoutSeconds, string diagnosticLog) {
        stop = false;
        worker = new Thread(delegate() {
            var until = DateTime.UtcNow.AddSeconds(timeoutSeconds);
            // Allow the child to enter raw mode before examining its screen.
            Thread.Sleep(1000);
            int ready = 0;
            bool commandSent = false;
            int enters = 0;
            DateTime nextEnter = DateTime.MaxValue;
            while (!stop && DateTime.UtcNow < until) {
                BufferInfo info;
                var output = GetStdHandle(-11);
                if (GetConsoleScreenBufferInfo(output, out info)) {
                    // Inline TUI can occupy the top of a tall terminal window;
                    // the composer is near the cursor, not the viewport bottom.
                    short top = info.Window.Top;
                    short bottom = (short)Math.Min(info.Window.Bottom, info.Cursor.Y + 5);
                    var text = new StringBuilder(info.Size.X * (bottom-top+1));
                    uint read;
                    ReadConsoleOutputCharacterW(output, text, (uint)(info.Size.X * (bottom-top+1)), new Coord { X=0, Y=top }, out read);
                    Trace(diagnosticLog, text.ToString());
                    if (commandSent) {
                        if (IsStatusVisible(text.ToString())) {
                            Trace(diagnosticLog, "STATUS_CONFIRMED: account/session status is visible.\n" + text.ToString());
                            return;
                        }
                        // Separate typing from Enter so Codex's fast-paste and
                        // slash-menu handling have finished before submission.
                        // A second Enter is allowed only while that same slash
                        // menu is still visible; never resend the command text.
                        string screen = text.ToString();
                        bool statusMenu = screen.IndexOf("show current session", StringComparison.OrdinalIgnoreCase) >= 0
                            && screen.IndexOf("/status", StringComparison.OrdinalIgnoreCase) >= 0;
                        if (DateTime.UtcNow >= nextEnter && enters < 2 && statusMenu) {
                            Send("\r");
                            enters++;
                            nextEnter = DateTime.UtcNow.AddSeconds(2);
                        }
                        Thread.Sleep(350);
                        continue;
                    }
                    ready = IsReady(text.ToString()) ? ready + 1 : 0;
                    if (ready >= 3) {
                        bool sent = Send("/status");
                        Trace(diagnosticLog, "Slash command typed: " + sent);
                        if (!sent) {
                            Console.WriteLine("\nCould not send /status to this tab. Type /status manually.");
                            return;
                        }
                        commandSent = true;
                        nextEnter = DateTime.UtcNow.AddSeconds(1.2);
                    }
                }
                Thread.Sleep(350);
            }
            if (!stop) Console.WriteLine("\nCould not confirm /status. Complete any Codex startup prompts, then type /status in this tab.");
        });
        worker.IsBackground = true;
        worker.Start();
    }
    public static void Stop() { stop = true; if (worker != null) worker.Join(1500); }
}
