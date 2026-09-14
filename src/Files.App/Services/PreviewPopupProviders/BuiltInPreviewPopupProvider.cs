// Copyright (c) Files Community
// Licensed under the MIT License.

using Files.App.Views.PreviewPopup;

namespace Files.App.Services.PreviewPopupProviders
{
	/// <summary>
	/// In-app Space preview. Always available so QuickLook does not need to be running.
	/// </summary>
	public sealed class BuiltInPreviewPopupProvider : IPreviewPopupProvider
	{
		public static BuiltInPreviewPopupProvider Instance { get; } = new();

		public Task<bool> DetectAvailability()
			=> Task.FromResult(true);

		public Task TogglePreviewPopupAsync(string path)
			=> MainWindow.Instance.DispatcherQueue.EnqueueOrInvokeAsync(() => PreviewPopupHost.ToggleAsync(path));

		public Task SwitchPreviewAsync(string path)
			=> MainWindow.Instance.DispatcherQueue.EnqueueOrInvokeAsync(() => PreviewPopupHost.SwitchAsync(path));
	}
}
