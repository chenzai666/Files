// Copyright (c) Files Community
// Licensed under the MIT License.

using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Xml.Linq;
using Windows.Management.Deployment;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.System.Com;
using Windows.Win32.UI.Shell;
using Windows.Win32.UI.WindowsAndMessaging;

namespace Files.App.Helpers.Application
{
	/// <summary>
	/// Launching <c>Files.exe</c> directly from a dev-registered package's folder
	/// does not grant package identity, so the Windows App SDK initialization
	/// fails with REGDB_E_CLASSNOTREG before <c>Main</c> runs. The module
	/// initializer hands such launches over to the packaged activation, making
	/// double-clicking the executable work like launching it from the Start menu.
	/// </summary>
	internal static unsafe class AppIdentityRelauncher
	{
		[ModuleInitializer]
		internal static void EnsurePackageIdentity()
		{
			if (HasPackageIdentity())
				return;

			RelaunchWithIdentity();

			// The relaunch either succeeded or explained the problem
			Environment.Exit(0);
		}

		/// <summary>
		/// Gets a value indicating whether the current process has package identity.
		/// </summary>
		private static bool HasPackageIdentity()
		{
			uint length = 0;
			return PInvoke.GetCurrentPackageFullName(ref length, default) != WIN32_ERROR.APPMODEL_ERROR_NO_PACKAGE;
		}

		/// <summary>
		/// Activates the packaged app entry through the system activation manager.
		/// </summary>
		private static void RelaunchWithIdentity()
		{
			string? appUserModelId = null;

			try
			{
				var exePath = Environment.ProcessPath;
				if (string.IsNullOrEmpty(exePath))
					return;

				var packageRoot = Path.GetDirectoryName(exePath)!;
				var manifestPath = Path.Combine(packageRoot, "AppxManifest.xml");
				if (!File.Exists(manifestPath))
					return;

				var manifest = XDocument.Load(manifestPath);
				var applicationId = manifest
					.Descendants()
					.FirstOrDefault(element => element.Name.LocalName == "Application")?
					.Attribute("Id")?.Value;
				if (string.IsNullOrEmpty(applicationId))
					return;

				var familyName = FindPackageFamilyName(packageRoot);
				if (string.IsNullOrEmpty(familyName))
					return;

				appUserModelId = $"{familyName}!{applicationId}";

				// The activation manager requires COM; the entry point has not initialized it yet
				if (PInvoke.OleInitialize(null).Failed)
					return;

				PInvoke.CoCreateInstance(typeof(ApplicationActivationManager).GUID, null, CLSCTX.CLSCTX_LOCAL_SERVER, out IApplicationActivationManager? activationManager);
				activationManager!.ActivateApplication(appUserModelId, BuildArguments(), ACTIVATEOPTIONS.AO_NONE, out _);

				// A packaged instance must exist after a successful activation
				Thread.Sleep(600);
				if (Process.GetProcessesByName("Files").Any(process => process.Id != Environment.ProcessId))
					return;

				throw new InvalidOperationException($"Activation of '{appUserModelId}' did not produce a running instance.");
			}
			catch (Exception ex)
			{
				PInvoke.MessageBox(
					default,
					$"无法直接启动 Files.exe（缺少包标识），自动转交包激活时也失败了。\n\n" +
					$"AUMID: {appUserModelId ?? "(unknown)"}\n" +
					$"错误：{ex.Message}\n\n" +
					$"请从开始菜单启动 “Files - Dev”，或重新运行安装器。",
					"Files",
					MESSAGEBOX_STYLE.MB_ICONERROR);
			}
		}

		/// <summary>
		/// Finds the package family name of the registered package whose install
		/// location contains the executable file.
		/// </summary>
		private static string? FindPackageFamilyName(string packageRoot)
		{
			var packages = new PackageManager().FindPackagesForUser(string.Empty);

			foreach (Windows.ApplicationModel.Package package in packages)
			{
				if (string.Equals(package.InstalledLocation, packageRoot, StringComparison.OrdinalIgnoreCase))
					return package.Id.FamilyName;
			}

			return null;
		}

		/// <summary>
		/// Forwards the command line of the identity-less process to the packaged app.
		/// </summary>
		private static string BuildArguments()
		{
			var args = Environment.GetCommandLineArgs();
			return args.Length > 1 ? string.Join(' ', args.Skip(1).Select(arg => $"\"{arg}\"")) : string.Empty;
		}
	}
}