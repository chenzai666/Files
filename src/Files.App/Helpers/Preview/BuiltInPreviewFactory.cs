// Copyright (c) Files Community
// Licensed under the MIT License.

using Files.App.UserControls.FilePreviews;
using Files.App.ViewModels.Previews;
using Files.Shared.Helpers;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;

namespace Files.App.Helpers.Preview
{
	/// <summary>
	/// Builds the same preview controls used by the info pane, for both the pane and the Space popup.
	/// </summary>
	internal static class BuiltInPreviewFactory
	{
		public static async Task<UserControl?> CreateAsync(
			ListedItem item,
			bool downloadItem,
			IContentPageContext contentPageContext,
			Action<bool>? setShowCloudItemButton = null)
		{
			setShowCloudItemButton?.Invoke(false);

			if (item.IsRecycleBinItem)
			{
				if (item.PrimaryItemAttribute == StorageItemTypes.Folder && !item.IsArchive)
				{
					var folderModel = new FolderPreviewViewModel(item);
					await folderModel.LoadAsync();
					return new FolderPreview(folderModel);
				}

				var recycleModel = new BasicPreviewViewModel(item);
				await recycleModel.LoadAsync();
				return new BasicPreview(recycleModel);
			}

			if (item.IsShortcut)
			{
				var shortcutModel = new ShortcutPreviewViewModel(item);
				await shortcutModel.LoadAsync();
				return new BasicPreview(shortcutModel);
			}

			if (FileExtensionHelpers.IsBrowsableZipFile(item.FileExtension, out _))
			{
				var archiveModel = new ArchivePreviewViewModel(item);
				await archiveModel.LoadAsync();
				return new BasicPreview(archiveModel);
			}

			if (item.PrimaryItemAttribute == StorageItemTypes.Folder)
			{
				var folderModel = new FolderPreviewViewModel(item);
				await folderModel.LoadAsync();
				return new FolderPreview(folderModel);
			}

			if (item.FileExtension is null)
				return null;

			if (item.SyncStatusUI.SyncStatus is CloudDriveSyncStatus.FileOnline && !downloadItem)
			{
				setShowCloudItemButton?.Invoke(true);
				return null;
			}

			var ext = item.FileExtension.ToLowerInvariant();

			if (!item.IsFtpItem &&
				contentPageContext.PageType != ContentPageTypes.ZipFolder &&
				(FileExtensionHelpers.IsAudioFile(ext) || FileExtensionHelpers.IsVideoFile(ext)))
			{
				var model = new MediaPreviewViewModel(item);
				await model.LoadAsync();
				return new MediaPreview(model);
			}

			if (FileExtensionHelpers.IsMarkdownFile(ext))
			{
				var model = new MarkdownPreviewViewModel(item);
				await model.LoadAsync();
				return new MarkdownPreview(model);
			}

			if (FileExtensionHelpers.IsImagePreviewFile(ext))
			{
				var model = new ImagePreviewViewModel(item);
				await model.LoadAsync();
				return new ImagePreview(model);
			}

			if (FileExtensionHelpers.IsPdfFile(ext))
			{
				var model = new PDFPreviewViewModel(item);
				await model.LoadAsync();
				return new PDFPreview(model);
			}

			if (FileExtensionHelpers.IsHtmlFile(ext))
			{
				var model = new HtmlPreviewViewModel(item);
				await model.LoadAsync();
				return new HtmlPreview(model);
			}

			if (FileExtensionHelpers.IsTextFile(ext))
			{
				var model = new TextPreviewViewModel(item);
				await model.LoadAsync();
				return new TextPreview(model);
			}

			if (FileExtensionHelpers.IsRichTextFile(ext))
			{
				var model = new RichTextPreviewViewModel(item);
				await model.LoadAsync();
				return new RichTextPreview(model);
			}

			if (CodePreviewViewModel.IsCodeFile(ext))
			{
				var model = new CodePreviewViewModel(item);
				await model.LoadAsync();
				return new CodePreview(model);
			}

			if (ShellPreviewViewModel.FindPreviewHandlerFor(item.FileExtension, 0) is not null &&
				!FileExtensionHelpers.IsFontFile(item.FileExtension) &&
				!FileExtensionHelpers.IsExecutableFile(item.FileExtension))
			{
				var model = new ShellPreviewViewModel(item);
				await model.LoadAsync();
				return new ShellPreview(model);
			}

			return await TextPreviewViewModel.TryLoadAsTextAsync(item);
		}

		public static async Task<UserControl> CreateOrBasicAsync(
			ListedItem item,
			bool downloadItem,
			IContentPageContext contentPageContext,
			Action<bool>? setShowCloudItemButton = null)
		{
			var control = await CreateAsync(item, downloadItem, contentPageContext, setShowCloudItemButton);
			if (control is not null)
				return control;

			var basicModel = new BasicPreviewViewModel(item);
			await basicModel.LoadAsync();
			return new BasicPreview(basicModel);
		}
	}
}
