// SPDX-License-Identifier: GPL-3.0-or-later
using QuickLook.Common.Plugin;
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Interop;
using System.Windows.Media;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Files.QuickLook.Host;

internal static class Program
{
    private static IViewer viewer;
    private static Application app;

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length != 3 || !long.TryParse(args[0], out var handle) ||
                !int.TryParse(args[1], out var processId))
                return 2;

            var parent = new HWND((IntPtr)handle);
            unsafe
            {
                uint actualProcessId;
                PInvoke.GetWindowThreadProcessId(parent, &actualProcessId);
                if (actualProcessId != processId)
                    return 2;
            }

            // Paths travel over the inherited pipe, never through a shell or public IPC endpoint.
            var path = Console.ReadLine();
            if (string.IsNullOrEmpty(path) || !Path.IsPathRooted(path) || !File.Exists(path))
                return 3;

            app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.DispatcherUnhandledException += (_, e) =>
            {
                e.Handled = true;
                app.Shutdown(1);
            };
            app.Exit += (_, _) => { try { viewer?.Cleanup(); } catch { } };

            var runtime = AppDomain.CurrentDomain.BaseDirectory;
            // Resolve dependencies only inside the packaged runtime; never scan the selected file's directory.
            AppDomain.CurrentDomain.AssemblyResolve += (_, e) =>
            {
                var name = new AssemblyName(e.Name).Name;
                if (name.EndsWith(".resources", StringComparison.OrdinalIgnoreCase))
                    return null;
                var file = Directory.EnumerateFiles(runtime, name + ".dll", SearchOption.AllDirectories).FirstOrDefault();
                return file == null ? null : Assembly.LoadFrom(file);
            };

            AddResources();
            viewer = FindViewer(runtime, path);
            if (viewer == null)
                return 4;

            var window = new Window
            {
                WindowStyle = WindowStyle.None,
                ResizeMode = ResizeMode.NoResize,
                ShowInTaskbar = false,
                ShowActivated = false,
                Width = 800,
                Height = 600,
                Background = args[2] == "dark" ? new SolidColorBrush(Color.FromRgb(32, 32, 32)) : Brushes.White
            };
            app.MainWindow = window;
            var context = new ContextObject { Source = window };
            var content = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
            content.SetBinding(ContentControl.ContentProperty, new Binding(nameof(ContextObject.ViewerContent)) { Source = context });
            window.Content = content;
            window.Closed += (_, _) => app.Shutdown();
            window.SourceInitialized += (_, _) => Embed(window, parent);
            window.Loaded += (_, _) =>
            {
                try
                {
                    viewer.Prepare(path, context);
                    viewer.View(path, context);
                    Console.WriteLine("READY");
                    Console.Out.Flush();
                }
                catch (Exception ex) { Console.Error.WriteLine(ex); app.Shutdown(1); }
            };

            // A closed stdin or dead owner ends the host, including when Files crashes.
            _ = Task.Run(() =>
            {
                try { Console.ReadLine(); } finally { app.Dispatcher.BeginInvoke(new Action(() => app.Shutdown())); }
            });
            _ = Task.Run(() =>
            {
                try { using (var owner = Process.GetProcessById(processId)) owner.WaitForExit(); }
                catch (ArgumentException) { }
                finally { app.Dispatcher.BeginInvoke(new Action(() => app.Shutdown())); }
            });
            window.Show();
            return app.Run();
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static IViewer FindViewer(string runtime, string path)
    {
        // This list deliberately excludes installers, executable previews and arbitrary user plugins.
        string[] names = { "ImageViewer", "PDFViewer", "TextViewer", "VideoViewer", "ArchiveViewer", "FontViewer", "MarkdownViewer" };
        foreach (var name in names)
        {
            var file = Path.Combine(runtime, "QuickLook.Plugin", "QuickLook.Plugin." + name, "QuickLook.Plugin." + name + ".dll");
            if (!File.Exists(file))
                continue;
            IViewer candidate = null;
            try
            {
                var type = Assembly.LoadFrom(file).GetExportedTypes().First(t => !t.IsAbstract && typeof(IViewer).IsAssignableFrom(t));
                candidate = (IViewer)Activator.CreateInstance(type);
                if (candidate.CanHandle(path))
                {
                    candidate.Init();
                    return candidate;
                }
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); }
            try { candidate?.Cleanup(); } catch { }
        }
        return null;
    }

    private static void AddResources()
    {
        // Plugin controls expect the same shared WPF styles as the upstream host.
        foreach (var uri in new[]
        {
            "pack://application:,,,/Wpf.Ui;component/Resources/Theme/Light.xaml",
            "pack://application:,,,/Wpf.Ui;component/Resources/Wpf.Ui.xaml",
            "pack://application:,,,/QuickLook.Common;component/Styles/ScrollBarStyleDictionary.xaml"
        })
        {
            try { app.Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri(uri) }); }
            catch { }
        }
        app.Resources["SegoeMDL2"] = new FontFamily("Segoe MDL2 Assets");
        app.Resources["SegoeFluent"] = new FontFamily("Segoe Fluent Icons");
    }

    private static unsafe void Embed(Window window, HWND parent)
    {
        var hwnd = new HWND(new WindowInteropHelper(window).Handle);
        PInvoke.SetWindowLong(hwnd, WINDOW_LONG_PTR_INDEX.GWL_STYLE,
            (int)(WINDOW_STYLE.WS_CHILD | WINDOW_STYLE.WS_VISIBLE | WINDOW_STYLE.WS_CLIPSIBLINGS));
        PInvoke.SetParent(hwnd, parent);
        PInvoke.GetClientRect(parent, out var rect);
        PInvoke.SetWindowPos(hwnd, HWND.Null, 0, 0, Math.Max(1, rect.Width), Math.Max(1, rect.Height),
            SET_WINDOW_POS_FLAGS.SWP_NOZORDER | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE | SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED);
    }
}
