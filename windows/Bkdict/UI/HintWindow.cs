using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Bkdict.Platform;

namespace Bkdict.UI;

/// "Ditar →" beside the hovered bar on a side, pointing at it, level with the microphone. It never takes focus or
/// the mouse (WS_EX_TRANSPARENT), so the bar under the cursor keeps its hover.
internal sealed class HintWindow : Window
{
    private const double Gap = 8, HintHeight = 34;
    /// The microphone's center, from the bar's top: 6 px padding + half of the 26 px button.
    private const double MicCenter = 19;
    private static readonly Color Osso = Color.FromRgb(0xF1, 0xEC, 0xE2);
    private static readonly Color Tinta = Color.FromRgb(0x0A, 0x0A, 0x0A);

    private readonly IntPtr handle;
    private readonly Border root;

    public HintWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        Focusable = false;
        IsHitTestVisible = false;

        root = new Border
        {
            Height = HintHeight, CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1),
            Background = Brush(Tinta, 0.94), BorderBrush = Brush(Osso, 0.14), Padding = new Thickness(12, 0, 12, 0),
            SnapsToDevicePixels = true,
        };
        root.SetResourceReference(TextElement.FontFamilyProperty, "BodyFont");
        Content = root;

        handle = new WindowInteropHelper(this).EnsureHandle();
        var style = Native.GetWindowLong(handle, Native.GWL_EXSTYLE);
        Native.SetWindowLong(handle, Native.GWL_EXSTYLE,
            style | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW | Native.WS_EX_TRANSPARENT);
    }

    private static SolidColorBrush Brush(Color color, double opacity = 1)
    {
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }

    /// `bar` is the bar's rectangle in physical pixels; the hint goes on its inner side, the arrow toward it.
    public void ShowBeside(Rect bar, string edge, double scale)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (edge == OverlayWindow.Edges.Left) row.Children.Add(Arrow("←", new Thickness(0, 0, 8, 0)));
        row.Children.Add(new TextBlock
        {
            Text = "Ditar", FontSize = 13, FontWeight = FontWeights.Medium, Foreground = Brush(Osso),
            VerticalAlignment = VerticalAlignment.Center,
        });
        if (edge == OverlayWindow.Edges.Right) row.Children.Add(Arrow("→", new Thickness(8, 0, 0, 0)));
        root.Child = row;

        root.Measure(new Size(double.PositiveInfinity, HintHeight));
        double w = Math.Ceiling(root.DesiredSize.Width * scale), h = Math.Round(HintHeight * scale), gap = Math.Round(Gap * scale);
        double x = edge == OverlayWindow.Edges.Right ? bar.X - gap - w : bar.Right + gap;
        double y = Math.Round(bar.Y + MicCenter * scale - h / 2);
        bool appearing = !IsVisible;
        if (appearing)
        {
            root.Opacity = 0;
            Show();
        }
        Native.SetWindowPos(handle, Native.HWND_TOPMOST, (int)x, (int)y, (int)w, (int)h, Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
        if (appearing) root.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.12)));
    }

    private static TextBlock Arrow(string arrow, Thickness margin) => new()
    {
        Text = arrow, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Brush(Osso, 0.6), Margin = margin,
        VerticalAlignment = VerticalAlignment.Center,
    };
}
