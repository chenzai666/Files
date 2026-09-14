// Copyright (c) Files Community
// Licensed under the MIT License.

using Microsoft.UI.Xaml;
using System.IO;

namespace Files.App.Services.PreviewPopupProviders;

internal sealed class EmbeddedQuickLookProvider : IPreviewPopupProvider
{
	internal static EmbeddedQuickLookProvider Instance { get; } = new();

	private readonly SemaphoreSlim gate = new(1, 1);
	private EmbeddedQuickLookSession? session;
	private string? currentPath;

	public Task<bool> DetectAvailability()
		=> Task.FromResult(EmbeddedQuickLookSession.IsAvailable);

	public async Task TogglePreviewPopupAsync(string path)
	{
		await gate.WaitAsync();
		try
		{
			if (session is not null && string.Equals(currentPath, path, StringComparison.OrdinalIgnoreCase))
			{
				CloseSession();
				return;
			}

			await ShowAsync(path);
		}
		finally
		{
			gate.Release();
		}
	}

	public async Task SwitchPreviewAsync(string path)
	{
		await gate.WaitAsync();
		try
		{
			if (session is not null && !string.Equals(currentPath, path, StringComparison.OrdinalIgnoreCase))
				await ShowAsync(path);
		}
		finally
		{
			gate.Release();
		}
	}

	private async Task ShowAsync(string path)
	{
		CloseSession();

		if (!Path.IsPathFullyQualified(path) || !File.Exists(path))
			return;

		var next = new EmbeddedQuickLookSession();
		next.Exited += Session_Exited;
		session = next;
		currentPath = path;

		try
		{
			var dark = MainWindow.Instance.Content is FrameworkElement root && root.ActualTheme == ElementTheme.Dark;
			await next.StartAsync(MainWindow.Instance.WindowHandle, path, dark, popup: true);
		}
		catch (Exception ex)
		{
			App.Logger.LogWarning("Embedded QuickLook popup failed: {ErrorType}", ex.GetType().Name);
			if (ReferenceEquals(session, next))
			{
				next.Exited -= Session_Exited;
				session = null;
				currentPath = null;
			}
			next.Dispose();
		}
	}

	private void CloseSession()
	{
		var old = session;
		session = null;
		currentPath = null;

		if (old is not null)
		{
			old.Exited -= Session_Exited;
			old.Dispose();
		}
	}

	private void Session_Exited(object? sender, EventArgs e)
	{
		if (sender is not EmbeddedQuickLookSession exited)
			return;

		MainWindow.Instance.DispatcherQueue.TryEnqueue(() =>
		{
			if (ReferenceEquals(session, exited))
			{
				exited.Exited -= Session_Exited;
				session = null;
				currentPath = null;
			}
		});
	}
}
