// Copyright (c) Files Community
// Licensed under the MIT License.

using System.Diagnostics;
using System.IO;

namespace Files.App.Services.PreviewPopupProviders;

internal sealed class EmbeddedQuickLookSession : IDisposable
{
	private Process? process;
	private readonly CancellationTokenSource lifetime = new();

	internal static string HostPath => Path.Combine(AppContext.BaseDirectory, "QuickLook", "Files.QuickLook.Host.exe");
	internal static bool IsAvailable => Environment.Is64BitProcess && File.Exists(HostPath);
	internal event EventHandler? Exited;

	internal async Task StartAsync(nint parent, string path, bool dark)
	{
		var startInfo = new ProcessStartInfo(HostPath)
		{
			UseShellExecute = false,
			CreateNoWindow = true,
			RedirectStandardInput = true,
			RedirectStandardOutput = true,
			WorkingDirectory = Path.GetDirectoryName(HostPath)!,
		};
		startInfo.ArgumentList.Add(parent.ToString(System.Globalization.CultureInfo.InvariantCulture));
		startInfo.ArgumentList.Add(Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture));
		startInfo.ArgumentList.Add(dark ? "dark" : "light");
		var child = Process.Start(startInfo) ?? throw new IOException("The embedded preview host did not start.");
		process = child;
		using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
		timeout.CancelAfter(TimeSpan.FromSeconds(20));
		await child.StandardInput.WriteLineAsync(path.AsMemory(), timeout.Token);
		await child.StandardInput.FlushAsync(timeout.Token);
		if (await child.StandardOutput.ReadLineAsync(timeout.Token) != "READY")
			throw new IOException("The embedded preview host could not load this file.");
		_ = ObserveExitAsync(child);
	}

	private async Task ObserveExitAsync(Process child)
	{
		try
		{
			await child.WaitForExitAsync(lifetime.Token);
			if (!lifetime.IsCancellationRequested)
				Exited?.Invoke(this, EventArgs.Empty);
		}
		catch (OperationCanceledException) { }
		catch (InvalidOperationException) { }
	}

	public void Dispose()
	{
		if (lifetime.IsCancellationRequested)
			return;
		lifetime.Cancel();
		var child = process;
		process = null;
		if (child is not null)
			_ = StopAsync(child);
	}

	private static async Task StopAsync(Process child)
	{
		try
		{
			child.StandardInput.Close();
			using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
			try { await child.WaitForExitAsync(timeout.Token); }
			catch (OperationCanceledException)
			{
				if (!child.HasExited)
					child.Kill(entireProcessTree: true);
			}
		}
		catch (InvalidOperationException) { }
		catch (IOException) { }
		catch (System.ComponentModel.Win32Exception) { }
		finally { child.Dispose(); }
	}
}
