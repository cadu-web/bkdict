using System;
using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;

namespace Bkdict.UI;

/// The notification-area icon (the macOS menu bar item).
public sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ToolStripMenuItem statusItem;
    private readonly Forms.ContextMenuStrip menu;
    private Forms.ToolStripMenuItem? meetingItem;

    public TrayIcon(Action open, Action copyLast, Action quit)
    {
        statusItem = new Forms.ToolStripMenuItem("Iniciando…") { Enabled = false };
        menu = new Forms.ContextMenuStrip();
        menu.Items.Add(statusItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Abrir BKDict", null, (_, _) => open());
        menu.Items.Add("Copiar última transcrição", null, (_, _) => copyLast());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Sair do BKDict", null, (_, _) => quit());

        icon = new Forms.NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "BKDict",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) open();
        };
    }

    public string Status
    {
        set
        {
            statusItem.Text = value;
            // NotifyIcon tooltips are limited to 63 characters.
            var tip = "BKDict — " + value;
            icon.Text = tip.Length > 63 ? tip[..62] + "…" : tip;
        }
    }

    /// Adds "Gravar reunião" under "Abrir BKDict"; its text follows SetMeetingRecording.
    public void SetMeetingAction(Action toggle)
    {
        meetingItem = new Forms.ToolStripMenuItem("Gravar reunião", null, (_, _) => toggle());
        menu.Items.Insert(3, meetingItem);
    }

    public void SetMeetingRecording(bool recording)
    {
        if (meetingItem != null) meetingItem.Text = recording ? "Parar gravação da reunião" : "Gravar reunião";
    }

    /// Offers a newer release: a menu item that opens its download page, and a one-time notification.
    public void ShowUpdate(string version, string url)
    {
        void Open() => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });
        menu.Items.Insert(2, new Forms.ToolStripMenuItem($"Baixar a versão {version}…", null, (_, _) => Open()));
        icon.BalloonTipClicked += (_, _) => Open();
        icon.ShowBalloonTip(8000, "BKDict", $"A versão {version} está disponível. Clique para baixar.", Forms.ToolTipIcon.Info);
    }

    private static Icon LoadIcon()
    {
        try
        {
            var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppIcon.png"));
            if (resource != null)
            {
                using var source = new Bitmap(resource.Stream);
                using var small = new Bitmap(source, new System.Drawing.Size(32, 32));
                return Icon.FromHandle(small.GetHicon());
            }
        }
        catch
        {
            // Fall back to the generic application icon.
        }
        return SystemIcons.Application;
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
