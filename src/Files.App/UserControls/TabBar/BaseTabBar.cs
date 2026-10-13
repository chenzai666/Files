// Copyright (c) Files Community
// Licensed under the MIT License.

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Runtime.CompilerServices;
using WinRT;

namespace Files.App.UserControls.TabBar
{
	/// <summary>
	/// Represents base class for <see cref="TabBar"/>.
	/// </summary>
	public abstract class BaseTabBar : UserControl, ITabBar, INotifyPropertyChanged
	{
		protected ITabBarItemContent? CurrentSelectedAppInstance;

		public static event EventHandler<ITabBar>? OnLoaded;
		public static event PropertyChangedEventHandler? StaticPropertyChanged;
		public event PropertyChangedEventHandler? PropertyChanged;

		public const string TabDropHandledIdentifier = "FilesTabViewItemDropHandled";

		public const string TabPaneSplitHandledIdentifier = "FilesTabPaneSplitHandled";

		public const string TabPathIdentifier = "FilesTabViewItemPath";

		public const string PaneDragIdentifier = "FilesPaneDragId";

		public const string ExternalTabDragFormat = "Files.ExternalTabDrag.v1";

		public const string ExternalTabDropHandledIdentifier = "FilesExternalTabDropHandled";

		// RecentlyClosedTabs is shared between all multitasking controls
		public static Stack<TabBarItemParameter[]> RecentlyClosedTabs { get; private set; } = new();

		public ObservableCollection<TabBarItem> Items
			=> MainPageViewModel.AppInstances;

		public event EventHandler<CurrentInstanceChangedEventArgs>? CurrentInstanceChanged;

		private static bool _IsRestoringClosedTab;
		public static bool IsRestoringClosedTab
		{
			get => _IsRestoringClosedTab;
			private set
			{
				_IsRestoringClosedTab = value;
				StaticPropertyChanged?.Invoke(null, new PropertyChangedEventArgs(nameof(IsRestoringClosedTab)));
			}
		}

		public BaseTabBar()
		{
			Loaded += TabView_Loaded;
		}

		public virtual DependencyObject? ContainerFromItem(ITabBarItem item)
		{
			return null;
		}

		protected void TabView_SelectionChanged(object? sender, SelectionChangedEventArgs? e)
		{
			if (App.AppModel.TabStripSelectedIndex < 0 || App.AppModel.TabStripSelectedIndex >= Items.Count)
				return;

			var nextInstance = GetCurrentSelectedTabInstance();
			if (nextInstance is null)
				return;

			OnCurrentInstanceChanged(new CurrentInstanceChangedEventArgs()
			{
				CurrentInstance = nextInstance
			});
		}

		protected void TabView_TabCloseRequested(TabView sender, TabViewTabCloseRequestedEventArgs args)
		{
			var tabItem = args.Item as TabBarItem;

			// Defer: removing inside the close-requested callback trips ObservableCollection reentrancy.
			DispatcherQueue.TryEnqueue(() => CloseTab(tabItem));
		}

		protected void OnCurrentInstanceChanged(CurrentInstanceChangedEventArgs args)
		{
			var nextInstance = args.CurrentInstance;
			if (ReferenceEquals(CurrentSelectedAppInstance, nextInstance) &&
				(nextInstance is null || nextInstance.IsCurrentInstance))
				return;

			// Only the departing and arriving pages change activation state.
			var previousInstance = CurrentSelectedAppInstance;
			CurrentSelectedAppInstance = nextInstance;
			if (previousInstance is not null && !ReferenceEquals(previousInstance, nextInstance))
				previousInstance.IsCurrentInstance = false;
			if (nextInstance is not null)
				nextInstance.IsCurrentInstance = true;

			args.PageInstances ??= GetAllTabInstances();
			CurrentInstanceChanged?.Invoke(this, args);
		}

		protected void NotifyPropertyChanged([CallerMemberName] string propertyName = "")
		{
			PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
		}

		public void TabView_Loaded(object sender, RoutedEventArgs e)
		{
			OnLoaded?.Invoke(null, this);
		}

		public ITabBarItemContent? GetCurrentSelectedTabInstance()
		{
			return MainPageViewModel.AppInstances[App.AppModel.TabStripSelectedIndex].TabItemContent;
		}

		public void SelectionChanged()
		{
			TabView_SelectionChanged(null, null);
		}

		public static void PushRecentTab(TabBarItemParameter[] tab)
		{
			RecentlyClosedTabs.Push(tab);
			StaticPropertyChanged?.Invoke(null, new PropertyChangedEventArgs(nameof(RecentlyClosedTabs)));
		}

		public List<ITabBarItemContent?> GetAllTabInstances()
		{
			return MainPageViewModel.AppInstances.Select(x => x.TabItemContent).ToList();
		}

		public async Task ReopenClosedTabAsync()
		{
			if (!IsRestoringClosedTab && RecentlyClosedTabs.Count > 0)
			{
				IsRestoringClosedTab = true;
				var lastTab = RecentlyClosedTabs.Pop();
				foreach (var item in lastTab)
					await NavigationHelpers.AddNewTabByParamAsync(item.InitialPageType, item.NavigationParameter);

				IsRestoringClosedTab = false;
			}
		}

		public async void MoveTabToNewWindowAsync(object sender, RoutedEventArgs e)
		{
			if (sender is not FrameworkElement { DataContext: TabBarItem tabItem })
				return;

			await MultitaskingTabsHelpers.MoveTabToNewWindow(tabItem, this);
		}

		[DynamicWindowsRuntimeCast(typeof(Frame))]
		public void CloseTab(TabBarItem? tabItem)
		{
			if (tabItem is null)
				return;

			if (MainWindow.Instance.Content is Frame rootFrame && rootFrame.Content is Files.App.Views.MainPage mainPage)
				mainPage.DetachTabContent(tabItem);

			Items.Remove(tabItem);
			tabItem.Unload();

			// Dispose and save tab arguments
			PushRecentTab([tabItem.NavigationParameter!]);

			// Save the updated tab list
			AppLifecycleHelper.SaveSessionTabs();

			AppMemoryHelper.RequestTrim();

			if (Items.Count == 0)
				MainWindow.Instance.Close();
		}

		[DynamicWindowsRuntimeCast(typeof(Control))]
		public void SetLoadingIndicatorStatus(ITabBarItem item, bool loading)
		{
			if (ContainerFromItem(item) is not Control tabItem)
				return;

			var stateToGoName = (loading) ? "Loading" : "NotLoading";

			VisualStateManager.GoToState(tabItem, stateToGoName, false);
		}
	}
}
