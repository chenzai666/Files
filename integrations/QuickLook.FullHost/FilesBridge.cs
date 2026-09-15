// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.Storage.Xps;

namespace QuickLook;

// Files supplies selection and lifetime; QuickLook owns viewers, windows and their actions.
internal static class FilesBridge
{
    internal static string SelectedPath { get; private set; }
    private static IntPtr ownerHandle;
    private static bool stopping;
    private static bool diagnostic;

    internal static unsafe void Start(App app, string[] args)
    {
        try
        {
            diagnostic = args.Length == 5 && args[3] == "--diagnostic-popup";
            if ((!diagnostic && (args.Length != 4 || args[3] != "--popup")) ||
                !long.TryParse(args[0], out var hwnd) || !int.TryParse(args[1], out var ownerPid) ||
                hwnd == 0 || ownerPid <= 0)
                throw new ArgumentException("Invalid Files owner.");
            uint actualPid;
            PInvoke.GetWindowThreadProcessId(new HWND((IntPtr)hwnd), &actualPid);
            if (actualPid != ownerPid) throw new ArgumentException("Files owner does not match.");
            ownerHandle = (IntPtr)hwnd;
            Console.SetIn(new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false, true)));
            SelectedPath = ReadPath(Console.ReadLine());
            Directory.CreateDirectory(App.LocalDataPath);
            app.DispatcherUnhandledException += (_, e) =>
            {
                Console.Error.WriteLine(e.Exception.GetType().Name);
                e.Handled = true;
                Stop();
            };
            TaskScheduler.UnobservedTaskException += (_, e) =>
            {
                Console.Error.WriteLine(e.Exception.GetType().Name);
                e.SetObserved();
            };
            PluginManager.GetInstance();
            ViewWindowManager.GetInstance().InvokePreview(SelectedPath);
            if (diagnostic) CaptureAfterLoad(args[4]);
            Console.WriteLine("READY");
            Console.Out.Flush();
            _ = ReadCommands();
            _ = Task.Run(() =>
            {
                try { using (var owner = Process.GetProcessById(ownerPid)) owner.WaitForExit(); }
                catch (ArgumentException) { }
                app.Dispatcher.BeginInvoke(new Action(Stop));
            });
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.GetType().Name);
            app.Shutdown(1);
        }
    }

    private static Task ReadCommands() => Task.Run(() =>
    {
        try
        {
            string line;
            while ((line = Console.ReadLine()) != null)
            {
                var parts = line.Split(new[] { '\t' }, 2);
                var command = parts[0];
                string path = null;
                try { if (parts.Length == 2) path = ReadPath(parts[1]); }
                catch (FileNotFoundException) { Console.Error.WriteLine("TARGET_UNAVAILABLE"); continue; }
                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (path != null) SelectedPath = path;
                    switch (command)
                    {
                        case "TOGGLE": ViewWindowManager.GetInstance().TogglePreview(path); break;
                        case "SWITCH": ViewWindowManager.GetInstance().SwitchPreview(path); break;
                        case "CLOSE": ViewWindowManager.GetInstance().ClosePreview(); break;
                        case "TEST_PIN" when diagnostic:
                            Application.Current.Windows.OfType<ViewerWindow>().First(w => w.IsVisible && !w.Pinned)
                                .buttonPin.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                            break;
                        case "TEST_STATE" when diagnostic:
                            var visible = Application.Current.Windows.OfType<ViewerWindow>().Where(w => w.IsVisible).ToArray();
                            Console.WriteLine("STATE\t" + visible.Length + "\t" + visible.Count(w => w.Pinned));
                            Console.Out.Flush();
                            break;
                        case "TEST_CLOSE_ALL" when diagnostic:
                            foreach (var active in Application.Current.Windows.OfType<ViewerWindow>().Where(w => w.IsVisible).ToArray()) active.Close();
                            break;
                        case "TEST_SPACE" when diagnostic:
                        case "TEST_ESCAPE" when diagnostic:
                            var window = Application.Current.Windows.OfType<ViewerWindow>().First(w => w.IsVisible);
                            window.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice,
                                PresentationSource.FromVisual(window), 0, command == "TEST_SPACE" ? Key.Space : Key.Escape)
                            { RoutedEvent = Keyboard.KeyDownEvent });
                            break;
                        default: throw new ArgumentException("Invalid preview command.");
                    }
                });
            }
        }
        catch (Exception ex) { Console.Error.WriteLine(ex.GetType().Name); }
        finally { Application.Current.Dispatcher.BeginInvoke(new Action(Stop)); }
    });

    private static string ReadPath(string path)
    {
        if (string.IsNullOrEmpty(path) || !Path.IsPathRooted(path) ||
            (!File.Exists(path) && !Directory.Exists(path)))
            throw new FileNotFoundException("Preview target is unavailable.");
        return path;
    }

    private static void CaptureAfterLoad(string target)
    {
        var ticks = 0;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        timer.Tick += (_, _) =>
        {
            var window = Application.Current.Windows.OfType<ViewerWindow>().FirstOrDefault(w => w.IsVisible);
            if ((window == null || window.ContextObject.IsBusy) && ++ticks < 10) return;
            timer.Stop();
            if (window == null) return;
            var handle = new HWND(new WindowInteropHelper(window).Handle);
            PInvoke.GetWindowRect(handle, out var bounds);
            using (var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height))
            using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
            {
                var hdc = graphics.GetHdc();
                try
                {
                    if (!PInvoke.PrintWindow(handle, new HDC(hdc), (PRINT_WINDOW_FLAGS)2))
                        throw new InvalidOperationException("Window capture failed.");
                }
                finally { graphics.ReleaseHdc(hdc); }
                bitmap.Save(target, System.Drawing.Imaging.ImageFormat.Png);
            }
        };
        timer.Start();
    }

    internal static void Attach(ViewerWindow window)
    {
        new WindowInteropHelper(window).Owner = ownerHandle;
        window.AddHandler(Keyboard.KeyDownEvent, new KeyEventHandler((_, e) =>
        {
            if (Keyboard.Modifiers != ModifierKeys.None || e.IsRepeat) return;
            if (e.Key == Key.Escape || e.Key == Key.Space)
            {
                e.Handled = true;
                window.Close();
            }
            else if (e.Key == Key.F11) window.ToggleFullscreen();
        }), true);
        window.Closed += (_, _) => Application.Current.Dispatcher.BeginInvoke(new Action(() =>
        {
            if (!stopping && !Application.Current.Windows.OfType<ViewerWindow>().Any(w => w.IsVisible)) Stop();
        }));
    }

    internal static void Dispatch(string command, string path, string[] options)
    {
        Application.Current.Dispatcher.BeginInvoke(new Action(() =>
        {
            var manager = ViewWindowManager.GetInstance();
            switch (command)
            {
                case PipeMessages.Toggle: manager.TogglePreview(path, string.Join(",", options ?? new string[0])); break;
                case PipeMessages.Switch: manager.SwitchPreview(path); break;
                case PipeMessages.Invoke: manager.InvokePreview(path); break;
                case PipeMessages.Close: manager.ClosePreview(); break;
                case PipeMessages.RunAndClose: manager.RunAndClosePreview(); break;
                case PipeMessages.Forget: manager.ForgetCurrentWindow(); break;
                case PipeMessages.Fullscreen: manager.ToggleFullscreen(); break;
                case PipeMessages.Quit: Stop(); break;
            }
        }));
    }

    private static void Stop()
    {
        if (stopping) return;
        stopping = true;
        Application.Current.Shutdown();
    }
}
