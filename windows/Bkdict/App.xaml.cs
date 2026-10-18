using System.Threading;
using System.Windows;
using Bkdict.Core;

namespace Bkdict;

/// Tray app: no window on its own; AppController owns the main window, overlay and shortcuts.
public partial class App : Application
{
    private Mutex? instanceMutex;
    private EventWaitHandle? showSignal;
    private AppController? controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // A second launch just brings the running instance's window forward.
        instanceMutex = new Mutex(true, "Bkdict.SingleInstance", out bool isFirst);
        showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, "Bkdict.ShowWindow");
        if (!isFirst)
        {
            showSignal.Set();
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            Log.Write("Unhandled: " + args.Exception);
            args.Handled = true;
        };

        controller = new AppController();
        controller.Start();

        var signal = showSignal;
        var listener = new Thread(() =>
        {
            while (signal.WaitOne())
            {
                Dispatcher.InvokeAsync(() => controller.ShowMainWindow());
            }
        }) { IsBackground = true };
        listener.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        controller?.Shutdown();
        base.OnExit(e);
    }
}
