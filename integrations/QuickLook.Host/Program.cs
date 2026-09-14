// SPDX-License-Identifier: GPL-3.0-or-later
using QuickLook.Common.Plugin;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
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
            var popup = args.Length == 4 && args[3] == "--popup";
            var diagnostic = args.Length == 5 && args[3] == "--diagnostic-snapshot";
            if ((!popup && !diagnostic && args.Length != 3) || !long.TryParse(args[0], out var handle) ||
                !int.TryParse(args[1], out var processId) || handle == 0 || processId <= 0)
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
            if (string.IsNullOrEmpty(path) || !Path.IsPathRooted(path) || (!File.Exists(path) && !Directory.Exists(path)))
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

            var isFolder = Directory.Exists(path);
            var window = new Window
            {
                WindowStyle = popup ? WindowStyle.SingleBorderWindow : WindowStyle.None,
                ResizeMode = popup ? ResizeMode.CanResize : ResizeMode.NoResize,
                ShowInTaskbar = popup,
                ShowActivated = popup,
                WindowStartupLocation = popup ? WindowStartupLocation.CenterOwner : WindowStartupLocation.Manual,
                Title = popup ? $"QuickLook - {GetDisplayName(path)}" : "Files QuickLook",
                Width = isFolder ? 453 : 800,
                Height = isFolder ? 172 : 600,
                Background = args[2] == "dark" ? new SolidColorBrush(Color.FromRgb(32, 32, 32)) : Brushes.White
            };
            app.MainWindow = window;
            var context = new ContextObject { Source = window, Theme = args[2] == "dark" ? Themes.Dark : Themes.Light };
            var content = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
            context.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName == nameof(ContextObject.ViewerContent))
                    content.Dispatcher.Invoke(() =>
                    {
                        content.Content = context.ViewerContent;
                        content.UpdateLayout();
                    });
            };
            window.Content = content;
            window.Closed += (_, _) => app.Shutdown();
            window.SourceInitialized += (_, _) => ConfigureWindow(window, parent, popup);
            window.Loaded += (_, _) =>
            {
                try
                {
                    viewer.Prepare(path, context);
                    viewer.View(path, context);
                    if (args.Length == 5)
                    {
                        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                        timer.Tick += async (_, _) =>
                        {
                            timer.Stop();
                            if (context.ViewerContent is ContentControl panel && panel.Content is WebView2 webView && webView.CoreWebView2 is CoreWebView2 core)
                            {
                                File.WriteAllText(args[4] + ".txt", core.Source + Environment.NewLine + await core.ExecuteScriptAsync("document.body.innerText"));
                                using (var output = File.Create(args[4]))
                                    await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, output);
                                return;
                            }
                            var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
                            bitmap.Render(window);
                            var encoder = new PngBitmapEncoder();
                            encoder.Frames.Add(BitmapFrame.Create(bitmap));
                            using (var output = File.Create(args[4])) encoder.Save(output);
                        };
                        timer.Start();
                    }
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
            return app.Run(window);
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static IViewer FindViewer(string runtime, string path)
    {
        var plugins = new List<IViewer>();
        var pluginRoot = Path.Combine(runtime, "QuickLook.Plugin");
        if (Directory.Exists(pluginRoot))
        {
            // Match QuickLook's plugin discovery, but keep the search rooted in
            // the package's read-only runtime. User plugin folders are excluded.
            foreach (var file in Directory.GetFiles(pluginRoot, "QuickLook.Plugin.*.dll", SearchOption.AllDirectories))
            {
                try
                {
                    foreach (var type in Assembly.LoadFrom(file).GetExportedTypes()
                        .Where(t => !t.IsInterface && !t.IsAbstract && typeof(IViewer).IsAssignableFrom(t)))
                    {
                        if (Activator.CreateInstance(type) is IViewer candidate)
                            plugins.Add(candidate);
                    }
                }
                catch (Exception ex) { Console.Error.WriteLine(ex); }
            }
        }

        plugins.Sort((left, right) => right.Priority.CompareTo(left.Priority));
        foreach (var plugin in plugins)
        {
            try
            {
                plugin.Init();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
            }
        }

        foreach (var plugin in plugins)
        {
            try
            {
                if (plugin.CanHandle(path))
                    return plugin;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                try { plugin.Cleanup(); } catch { }
            }
        }

        // QuickLook's built-in fallback shows metadata for folders and files
        // that do not have a specialized viewer.
        var infoPanel = new global::QuickLook.Plugin.InfoPanel.Plugin();
        infoPanel.Init();
        return infoPanel;
    }

    private static string GetDisplayName(string path)
    {
        var trimmed = path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (trimmed.Length == 0)
            return path;

        return Path.GetFileName(trimmed) is { Length: > 0 } name ? name : trimmed;
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

    private static void ConfigureWindow(Window window, HWND parent, bool popup)
    {
        if (popup)
        {
            new WindowInteropHelper(window).Owner = parent;
            return;
        }

        Embed(window, parent);
    }

    private static unsafe void Embed(Window window, HWND parent)
    {
        var hwnd = new HWND(new WindowInteropHelper(window).Handle);
        PInvoke.SetWindowLong(hwnd, WINDOW_LONG_PTR_INDEX.GWL_STYLE,
            (int)(WINDOW_STYLE.WS_CHILD | WINDOW_STYLE.WS_VISIBLE | WINDOW_STYLE.WS_CLIPSIBLINGS));
        PInvoke.SetParent(hwnd, parent);
        if (PInvoke.GetParent(hwnd) != parent)
            throw new InvalidOperationException("The preview window could not be embedded.");
        PInvoke.GetClientRect(parent, out var rect);
        PInvoke.SetWindowPos(hwnd, HWND.Null, 0, 0, Math.Max(1, rect.Width), Math.Max(1, rect.Height),
            SET_WINDOW_POS_FLAGS.SWP_NOZORDER | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE | SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED);
    }
}
