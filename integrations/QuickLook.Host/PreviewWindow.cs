// SPDX-License-Identifier: GPL-3.0-or-later
using QuickLook.Common.Helpers;
using QuickLook.Common.Plugin;
using QuickLook.Common.Plugin.MoreMenu;
using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;

namespace Files.QuickLook.Host;

internal sealed class PreviewWindow : Window
{
    private readonly ContextObject context;
    private readonly Grid root = new Grid();
    private readonly DockPanel caption = new DockPanel { Height = 32, VerticalAlignment = VerticalAlignment.Top };
    private readonly ContentControl content = new ContentControl
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch,
        VerticalContentAlignment = VerticalAlignment.Stretch
    };
    private readonly string path;
    private IViewer viewer;
    private readonly Action<IViewer> viewerChanged;
    private readonly DispatcherTimer loadTimeout = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
    private readonly Button maximize;

    internal PreviewWindow(ContextObject context, IViewer viewer, string path, Action<IViewer> viewerChanged)
    {
        this.context = context;
        this.viewer = viewer;
        this.viewerChanged = viewerChanged;
        this.path = path;
        context.Source = this;
        WindowStyle = WindowStyle.None;
        ShowActivated = false;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        UseLayoutRounding = true;
        MinWidth = 400;
        MinHeight = 160;
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 32, ResizeBorderThickness = new Thickness(6),
            GlassFrameThickness = new Thickness(1), UseAeroCaptionButtons = false
        });
        SetResourceReference(BackgroundProperty, "MainWindowBackgroundNoTransparent");
        SetResourceReference(ForegroundProperty, "WindowTextForeground");
        root.Children.Add(content);
        root.Children.Add(caption);
        Content = root;
        AddButton("\uE894", "Window_Close", "关闭", (_, _) => Close(), true);
        maximize = AddButton("\uE740", "Window_Maximize", "最大化 / 还原", (_, _) =>
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized);
        AddButton("\uE8E5", "Window_Open", "打开文件", (_, _) => OpenFile());
        var more = AddButton("\uE712", "Window_More", "更多", (_, _) => { });
        more.Click += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = more };
            if (viewer is IMoreMenu provider && provider.MenuItems != null)
                foreach (var item in provider.MenuItems) AddMenuItem(menu, item);
            var reload = new MenuItem { Header = TranslationHelper.Get("Window_Reload", failsafe: "重新加载") };
            reload.Click += (_, _) => LoadPreview();
            menu.Items.Add(reload);
            var copy = new MenuItem { Header = TranslationHelper.Get("Window_CopyAsPath", failsafe: "复制路径") };
            copy.Click += (_, _) => Clipboard.SetText(path);
            menu.Items.Add(copy);
            menu.IsOpen = true;
        };
        var top = AddButton("\uE74A", "Window_AlwaysOnTop", "置顶", (_, _) => { });
        DockPanel.SetDock(top, Dock.Left);
        top.Click += (_, _) => { Topmost = !Topmost; top.Opacity = Topmost ? 1 : 0.6; };
        var title = new TextBlock
        {
            Margin = new Thickness(5, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center,
            FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis
        };
        title.SetBinding(TextBlock.TextProperty, new Binding(nameof(ContextObject.Title)) { Source = context });
        caption.Children.Add(title);
        context.PropertyChanged += (_, _) => Dispatcher.Invoke(ApplyContext);
        loadTimeout.Tick += (_, _) =>
        {
            loadTimeout.Stop();
            if (context.IsBusy || context.ViewerContent == null) ShowSummary();
        };
        Closed += (_, _) => loadTimeout.Stop();
        // Keep Files focused on opening; handle dismissal after the user clicks the preview.
        AddHandler(Keyboard.KeyDownEvent, new KeyEventHandler((_, e) =>
        {
            if ((e.Key == Key.Space || e.Key == Key.Escape) && Keyboard.Modifiers == ModifierKeys.None && !e.IsRepeat)
            {
                e.Handled = true;
                Close();
            }
        }), true);
        MouseLeftButtonDown += (_, e) =>
        {
            if (context.FullWindowDragging && e.ButtonState == MouseButtonState.Pressed) DragMove();
        };
        MouseMove += (_, e) =>
        {
            caption.Visibility = !context.TitlebarAutoHide || e.GetPosition(this).Y <= 40
                ? Visibility.Visible : Visibility.Hidden;
        };
    }

    internal void LoadPreview()
    {
        try { RenderPreview(); }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.GetType().Name);
            if (!ShowSummary()) throw;
        }
    }

    internal bool ShowSummary()
    {
        loadTimeout.Stop();
        if (viewer is global::QuickLook.Plugin.InfoPanel.Plugin) return false;
        try { viewer.Cleanup(); } catch { }
        viewer = new global::QuickLook.Plugin.InfoPanel.Plugin();
        viewerChanged(viewer);
        viewer.Init();
        var theme = context.Theme;
        context.Reset();
        context.Theme = theme;
        RenderPreview();
        return true;
    }

    private void RenderPreview()
    {
        loadTimeout.Stop();
        viewer.Cleanup();
        context.ViewerContent = null;
        context.IsBusy = true;
        viewer.Prepare(path, context);
        var size = context.PreferredSize;
        var area = SystemParameters.WorkArea;
        Width = Math.Min(area.Width, Math.Max(MinWidth, size.Width));
        Height = Math.Min(area.Height, Math.Max(MinHeight, size.Height + (context.TitlebarOverlap ? 0 : 32)));
        viewer.View(path, context);
        ApplyContext();
        if (context.IsBusy || context.ViewerContent == null) loadTimeout.Start();
    }

    private void ApplyContext()
    {
        content.Content = context.ViewerContent;
        content.Margin = new Thickness(0, context.TitlebarOverlap ? 0 : 32, 0, 0);
        Title = "QuickLook - " + context.Title;
        ResizeMode = context.CanResize ? ResizeMode.CanResize : ResizeMode.NoResize;
        maximize.Visibility = context.CanResize ? Visibility.Visible : Visibility.Collapsed;
        caption.Background = context.TitlebarColourVisibility
            ? (Brush)FindResource("CaptionBackground") : Brushes.Transparent;
    }

    private Button AddButton(string glyph, string key, string fallback, RoutedEventHandler click, bool close = false)
    {
        var button = new Button
        {
            Content = glyph, ToolTip = TranslationHelper.Get(key, failsafe: fallback),
            Style = (Style)FindResource(close ? "CaptionCloseButtonStyle" : "CaptionButtonStyle")
        };
        DockPanel.SetDock(button, Dock.Right);
        button.Click += click;
        caption.Children.Add(button);
        return button;
    }

    private static void AddMenuItem(ItemsControl parent, IMenuItem item)
    {
        if (item == null) return;
        if (item.IsSeparator) { parent.Items.Add(new Separator()); return; }
        var menu = new MenuItem { DataContext = item };
        foreach (var property in new[] { MenuItem.HeaderProperty, MenuItem.CommandProperty,
            MenuItem.CommandParameterProperty, IsEnabledProperty, ToolTipProperty })
            menu.SetBinding(property, new Binding(property.Name));
        menu.SetBinding(VisibilityProperty, new Binding(nameof(IMenuItem.IsVisible))
        { Converter = new BooleanToVisibilityConverter() });
        if (item.MenuItems != null)
            foreach (var child in item.MenuItems) AddMenuItem(menu, child);
        parent.Items.Add(menu);
    }

    private void OpenFile()
    {
        try
        {
            using (Process.Start(new ProcessStartInfo(path) { UseShellExecute = true })) { }
            Close();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
