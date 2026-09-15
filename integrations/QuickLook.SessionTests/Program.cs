using Files.App.Services.PreviewPopupProviders;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length < 2) throw new ArgumentException("至少提供两个已存在的测试文件路径。");
        using var owner = new Form { Text = "Files 原始会话代码测试", Width = 900, Height = 700 };
        owner.Show();
        using var session = new EmbeddedQuickLookSession();
        var exited = false;
        session.Exited += (_, _) => exited = true;
        Pump(session.StartAsync(owner.Handle, args[0], dark: false, popup: true));
        foreach (var path in args.Skip(1))
        {
            var send = session.SendAsync("SWITCH", path);
            Pump(send);
            if (!send.Result || exited) throw new InvalidOperationException("切换预览失败。");
            Pump(Task.Delay(1000));
        }
        var close = session.SendAsync("TOGGLE", args[args.Length - 1]);
        Pump(close);
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (!exited && DateTime.UtcNow < deadline)
        {
            Application.DoEvents();
            Thread.Sleep(10);
        }
        if (!exited) throw new InvalidOperationException("再次空格预览后，宿主未退出。");
        Console.WriteLine("PASS: Files 原始发送代码、UTF-8 路径、连续切换、重复切换关闭及进程退出。");
        return 0;
    }

    private static void Pump(Task task)
    {
        var deadline = DateTime.UtcNow.AddSeconds(30);
        while (!task.IsCompleted && DateTime.UtcNow < deadline)
        {
            Application.DoEvents();
            Thread.Sleep(10);
        }
        if (!task.IsCompleted) throw new TimeoutException("会话测试超时。");
        task.GetAwaiter().GetResult();
    }
}
