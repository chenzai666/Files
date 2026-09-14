// Copyright (c) Files Community
// Licensed under the MIT License.

using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using WinRT;

namespace Files.App.Views.PreviewPopup
{
	/// <summary>
	/// QuickLook-style preview window hosted inside Files. Space toggles it; no external app required.
	/// </summary>
	internal static class PreviewPopupHost
	{
		private static WindowEx? _window;
		private static PreviewPopupPage? _page;
		private static string? _openPath;

		public static bool IsOpen => _window is not null && _page is not null;

		[DynamicWindowsRuntimeCast(typeof(OverlappedPresenter))]
		public static async Task ToggleAsync(string path)
		{
			if (IsOpen && string.Equals(_openPath, path, StringComparison.OrdinalIgnoreCase))
			{
				Close();
				return;
			}

			await ShowAsync(path);
		}

		[DynamicWindowsRuntimeCast(typeof(OverlappedPresenter))]
		public static async Task ShowAsync(string path)
		{
			var item = ResolveItem(path);
			if (item is null)
				return;

			EnsureWindow();
			_openPath = path;
			if (_page is not null)
				await _page.ShowItemAsync(item);

			_window?.AppWindow.Show();
			_window?.Activate();
		}

		public static async Task SwitchAsync(string path)
		{
			if (!IsOpen)
				return;

			var item = ResolveItem(path);
			if (item is null)
				return;

			_openPath = path;
			if (_page is not null)
				await _page.ShowItemAsync(item);
		}

		public static void Close()
		{
			if (_window is null)
				return;

			_page?.UnloadPreview();
			_window.Close();
		}

		public static void SelectAdjacent(int delta)
		{
			var context = Ioc.Default.GetRequiredService<IContentPageContext>();
			var shell = context.ShellPage;
			var items = shell?.ShellViewModel?.FilesAndFolders;
			if (items is null || items.Count == 0)
				return;

			var currentPath = context.SelectedItem?.ItemPath ?? _openPath;
			var list = items.ToList();
			var idx = list.FindIndex(i => string.Equals(i.ItemPath, currentPath, StringComparison.OrdinalIgnoreCase));
			if (idx < 0)
				idx = 0;

			var next = idx + delta;
			if (next < 0 || next >= list.Count)
				return;

			var target = list[next];
			shell!.SlimContentPage?.ItemManipulationModel.SetSelectedItem(target);
			shell.SlimContentPage?.ItemManipulationModel.ScrollIntoView(target);
		}

		[DynamicWindowsRuntimeCast(typeof(OverlappedPresenter))]
		private static void EnsureWindow()
		{
			if (_window is not null)
				return;

			var themeService = Ioc.Default.GetRequiredService<IAppThemeModeService>();
			_page = new PreviewPopupPage();
			var window = new WindowEx(480, 360)
			{
				ExtendsContentIntoTitleBar = true,
				IsMaximizable = true,
				IsMinimizable = false,
				Content = _page,
				SystemBackdrop = new AppSystemBackdrop(true),
			};
			window.SetTitleBar(_page.TitleBarElement);
			window.Closed += (_, _) =>
			{
				_page?.UnloadPreview();
				_page = null;
				_window = null;
				_openPath = null;
			};

			var appWindow = window.AppWindow;
			appWindow.Title = "Preview";
			appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
			appWindow.SetIcon(AppLifecycleHelper.AppIconPath);

			if (appWindow.Presenter is OverlappedPresenter presenter)
			{
				presenter.IsAlwaysOnTop = true;
				presenter.IsMinimizable = false;
			}

			themeService.SetAppThemeMode(window, appWindow.TitleBar, themeService.AppThemeMode, callThemeModeChangedEvent: false);

			var displayArea = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Nearest)
				?? DisplayArea.Primary;
			var work = displayArea.WorkArea;
			var width = Math.Max(640, (int)(work.Width * 0.72));
			var height = Math.Max(480, (int)(work.Height * 0.78));
			appWindow.Resize(new SizeInt32(width, height));
			appWindow.Move(new PointInt32(
				work.X + (work.Width - width) / 2,
				work.Y + (work.Height - height) / 2));

			_window = window;
		}

		private static ListedItem? ResolveItem(string path)
		{
			var context = Ioc.Default.GetRequiredService<IContentPageContext>();
			if (context.SelectedItem is { } selected &&
				string.Equals(selected.ItemPath, path, StringComparison.OrdinalIgnoreCase))
			{
				return selected;
			}

			return context.ShellPage?.ShellViewModel?.FilesAndFolders
				.FirstOrDefault(i => string.Equals(i.ItemPath, path, StringComparison.OrdinalIgnoreCase));
		}
	}
}
