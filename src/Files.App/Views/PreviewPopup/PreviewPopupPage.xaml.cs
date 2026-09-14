// Copyright (c) Files Community
// Licensed under the MIT License.

using Files.App.Helpers.Preview;
using Files.App.UserControls.FilePreviews;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Files.App.Views.PreviewPopup
{
	public sealed partial class PreviewPopupPage : Page
	{
		public UIElement TitleBarElement => TitleBarGrid;

		private UserControl? _preview;
		private CancellationTokenSource? _cts;

		public PreviewPopupPage()
		{
			InitializeComponent();

			KeyDown += PreviewPopupPage_KeyDown;
		}

		public async Task ShowItemAsync(ListedItem item)
		{
			_cts?.Cancel();
			_cts = new CancellationTokenSource();
			var token = _cts.Token;

			UnloadPreview();
			TitleText.Text = item.Name;
			LoadingRing.IsActive = true;
			LoadingRing.Visibility = Visibility.Visible;

			UserControl? control = null;
			try
			{
				var context = Ioc.Default.GetRequiredService<IContentPageContext>();
				control = await BuiltInPreviewFactory.CreateOrBasicAsync(item, downloadItem: true, context);
			}
			catch
			{
				control = null;
			}

			if (token.IsCancellationRequested)
			{
				if (control is ShellPreview cancelledShell)
					cancelledShell.UnloadPreview();
				return;
			}

			LoadingRing.IsActive = false;
			LoadingRing.Visibility = Visibility.Collapsed;

			if (control is null)
			{
				PreviewHost.Children.Add(new TextBlock
				{
					Text = "无法预览此文件",
					HorizontalAlignment = HorizontalAlignment.Center,
					VerticalAlignment = VerticalAlignment.Center,
				});
				return;
			}

			_preview = control;
			PreviewHost.Children.Add(control);
			Focus(FocusState.Programmatic);
		}

		public void UnloadPreview()
		{
			if (_preview is ShellPreview shellPreview)
				shellPreview.UnloadPreview();

			PreviewHost.Children.Clear();
			_preview = null;
		}

		private void PreviewPopupPage_KeyDown(object sender, KeyRoutedEventArgs e)
		{
			switch (e.Key)
			{
				case VirtualKey.Escape:
				case VirtualKey.Space:
					e.Handled = true;
					PreviewPopupHost.Close();
					break;
				case VirtualKey.Left:
				case VirtualKey.Up:
					e.Handled = true;
					PreviewPopupHost.SelectAdjacent(-1);
					break;
				case VirtualKey.Right:
				case VirtualKey.Down:
					e.Handled = true;
					PreviewPopupHost.SelectAdjacent(1);
					break;
			}
		}
	}
}
