using System;
using System.Windows;
using System.Windows.Media;
using Bkdict.Core;
using Microsoft.Win32;

namespace Bkdict.UI;

/// BKDG colors for light and dark. Written straight into Application.Resources, which wins over the
/// Fluent theme's merged dictionary, so the Fluent controls pick up the brand through their own keys.
public static class Brand
{
    private sealed record Palette(
        uint Background, uint Sidebar, uint Card, uint Border, uint Text, uint Secondary, uint Tertiary,
        uint Accent, byte AccentTintAlpha, uint Hover, byte HoverAlpha, uint Error);

    private static readonly Palette Light = new(
        Background: 0xFFFFFF, Sidebar: 0xF7F7F7, Card: 0xFFFFFF, Border: 0xD9D5CC,
        Text: 0x0A0A0A, Secondary: 0x4A4A45, Tertiary: 0x7D7B73,
        Accent: 0x611E2C, AccentTintAlpha: 0x14, Hover: 0x000000, HoverAlpha: 0x0A, Error: 0x7A2E22);

    // Bordô #611E2C gives 1.63:1 on Tinta and disappears; dark mode uses the lighter #B33751 (3.38:1).
    private static readonly Palette Dark = new(
        Background: 0x0A0A0A, Sidebar: 0x111110, Card: 0x151514, Border: 0x2A2926,
        Text: 0xF1ECE2, Secondary: 0xBDB8AE, Tertiary: 0x8C877D,
        Accent: 0xB33751, AccentTintAlpha: 0x1F, Hover: 0xF1ECE2, HoverAlpha: 0x0F, Error: 0xC8644F);

    /// Bordô with Osso on top: the flat accent surface, the same in both themes.
    public const uint Bordo = 0x611E2C;
    public const uint Osso = 0xF1ECE2;
    public const uint Tinta = 0x0A0A0A;

    private static Appearance current = Appearance.System;
    private static bool listening;

    public static void Apply(Appearance theme)
    {
        current = theme;
        if (!listening)
        {
            listening = true;
            SystemEvents.UserPreferenceChanged += (_, e) =>
            {
                if (e.Category == UserPreferenceCategory.General && current == Appearance.System)
                    Application.Current?.Dispatcher.InvokeAsync(() => Write(SystemIsDark() ? Dark : Light));
            };
        }
        Write(theme switch
        {
            Appearance.Light => Light,
            Appearance.Dark => Dark,
            _ => SystemIsDark() ? Dark : Light,
        });
    }

    private static void Write(Palette p)
    {
        var r = Application.Current.Resources;
        var accent = Brush(p.Accent);

        r["BrandBackground"] = Brush(p.Background);
        r["BrandSidebar"] = Brush(p.Sidebar);
        r["BrandCard"] = Brush(p.Card);
        r["BrandBorder"] = Brush(p.Border);
        r["BrandText"] = Brush(p.Text);
        r["BrandSecondary"] = Brush(p.Secondary);
        r["BrandTertiary"] = Brush(p.Tertiary);
        r["BrandAccent"] = accent;
        r["BrandAccentTint"] = Brush(p.Accent, p.AccentTintAlpha);
        r["BrandHover"] = Brush(p.Hover, p.HoverAlpha);
        r["BrandError"] = Brush(p.Error);
        r["BrandAccentSurface"] = Brush(Bordo);
        r["BrandOnAccent"] = Brush(Osso);

        // Fluent theme keys, so stock controls (buttons, toggles, selection, focus) follow the brand.
        foreach (var key in new[] { "SystemAccentColor", "SystemAccentColorLight1", "SystemAccentColorLight2",
                     "SystemAccentColorLight3", "SystemAccentColorDark1", "SystemAccentColorDark2", "SystemAccentColorDark3" })
            r[key] = ColorOf(p.Accent);
        foreach (var key in new[] { "AccentFillColorDefaultBrush", "AccentFillColorSecondaryBrush",
                     "AccentFillColorTertiaryBrush", "AccentTextFillColorPrimaryBrush", "AccentTextFillColorSecondaryBrush",
                     "AccentTextFillColorTertiaryBrush", "SystemFillColorAttentionBrush" })
            r[key] = accent;
        r["TextOnAccentFillColorPrimaryBrush"] = Brush(Osso);
        r["TextOnAccentFillColorSecondaryBrush"] = Brush(Osso, 0xB3);
        r["ApplicationBackgroundBrush"] = Brush(p.Background);
        r["CardBackgroundFillColorDefaultBrush"] = Brush(p.Card);
        r["CardStrokeColorDefaultBrush"] = Brush(p.Border);
        r["TextFillColorPrimaryBrush"] = Brush(p.Text);
        r["TextFillColorSecondaryBrush"] = Brush(p.Secondary);
        r["TextFillColorTertiaryBrush"] = Brush(p.Tertiary);
        r["SubtleFillColorSecondaryBrush"] = Brush(p.Hover, p.HoverAlpha);
    }

    private static bool SystemIsDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
        catch
        {
            return false;
        }
    }

    public static Color ColorOf(uint rgb, byte alpha = 0xFF) =>
        Color.FromArgb(alpha, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    public static SolidColorBrush Brush(uint rgb, byte alpha = 0xFF)
    {
        var brush = new SolidColorBrush(ColorOf(rgb, alpha));
        brush.Freeze();
        return brush;
    }
}
