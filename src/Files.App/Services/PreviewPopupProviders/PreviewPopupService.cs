// Copyright (c) Files Community
// SPDX-License-Identifier: MPL-2.0

namespace Files.App.Services.PreviewPopupProviders
{
	/// <inheritdoc cref="IPreviewPopupService"/>
	internal sealed partial class PreviewPopupService : ObservableObject, IPreviewPopupService
	{
		public async Task<IPreviewPopupProvider?> GetProviderAsync()
		{
			// Built-in Space preview is always available (no QuickLook process).
			if (await BuiltInPreviewPopupProvider.Instance.DetectAvailability())
				return BuiltInPreviewPopupProvider.Instance;

			if (await QuickLookProvider.Instance.DetectAvailability())
				return QuickLookProvider.Instance;
			if (await SeerProProvider.Instance.DetectAvailability())
				return SeerProProvider.Instance;
			if (await PowerToysPeekProvider.Instance.DetectAvailability())
				return PowerToysPeekProvider.Instance;

			return null;
		}
	}
}
