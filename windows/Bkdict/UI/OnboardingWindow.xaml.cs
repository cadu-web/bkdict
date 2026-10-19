using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Bkdict.Core;
using Bkdict.Platform;
using Microsoft.Win32;

namespace Bkdict.UI;

/// First-launch setup: the microphone and a transcription model, on one screen (the Mac also asks for
/// Accessibility; Windows needs no permission for the shortcut or for pasting).
public partial class OnboardingWindow : Window
{
    private const string MicrophoneConsent =
        @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
    private const string Recommended = "ggml-large-v3-turbo-q5_0.bin";

    private readonly AppModel model;
    private readonly Action onFinish;
    private readonly Action chooseModel;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(0.5) };
    private readonly AudioRecorder meter = new();
    private readonly Rectangle[] bars = new Rectangle[14];
    private readonly float[] levels = new float[14];
    private bool metering;
    private bool finished;

    private readonly Row microphone;
    private readonly Row transcription;
    private readonly StackPanel microphoneTest;
    private readonly ComboBox microphoneBox = new() { Width = 170, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button microphoneSettings;
    private readonly ProgressBar progress = new() { Width = 110, Height = 4, Maximum = 1, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button chooseButton;

    /// Needed until it's finished once. Someone who already has a model and the whisper server skips it;
    /// `Bkdict.exe --onboarding` shows it again.
    public static bool IsNeeded(AppModel model)
    {
        if (Environment.GetCommandLineArgs().Contains("--onboarding")) return true;
        if (AppSettings.Current.OnboardingDone) return false;
        if (MicrophoneAllowed() && TranscriptionReady(model))
        {
            model.OnboardingDone = true;
            return false;
        }
        return true;
    }

    public OnboardingWindow(AppModel model, Action chooseModel, Action onFinish)
    {
        InitializeComponent();
        this.model = model;
        this.chooseModel = chooseModel;
        this.onFinish = onFinish;
        Subtitle.Text = $"Segure {model.DictateLabel}, fale e solte: o texto aparece onde o cursor estiver. Falta só isto:";

        microphoneTest = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var waveform = new StackPanel { Orientation = Orientation.Horizontal, Height = 18, Margin = new Thickness(0, 0, 10, 0) };
        for (int i = 0; i < bars.Length; i++)
        {
            bars[i] = new Rectangle { Width = 3, Height = 3, RadiusX = 1, RadiusY = 1, Margin = new Thickness(0, 0, 2, 0), VerticalAlignment = VerticalAlignment.Center };
            bars[i].SetResourceReference(Shape.FillProperty, "BrandAccent");
            waveform.Children.Add(bars[i]);
        }
        microphoneTest.Children.Add(waveform);
        microphoneTest.Children.Add(microphoneBox);
        LoadMicrophones();
        microphoneBox.SelectionChanged += (_, _) =>
        {
            if (microphoneBox.SelectedItem is ComboBoxItem { Tag: string id } && id != model.Microphone)
            {
                model.Microphone = id;
                if (metering) StartMeter();
            }
        };
        microphoneSettings = new Button { Content = "Abrir configurações", Style = (Style)FindResource("PrimaryButton") };
        microphoneSettings.Click += (_, _) => Open("ms-settings:privacy-microphone");

        chooseButton = new Button { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        chooseButton.Click += (_, _) => chooseModel();

        microphone = new Row("Liberar o microfone", divider: true);
        microphone.Trailing.Children.Add(microphoneTest);
        microphone.Trailing.Children.Add(microphoneSettings);
        transcription = new Row("Preparar a transcrição", divider: false);
        transcription.Trailing.Children.Add(progress);
        transcription.Trailing.Children.Add(chooseButton);
        Items.Children.Add(microphone.Root);
        Items.Children.Add(transcription.Root);

        meter.LevelChanged += level => Dispatcher.InvokeAsync(() => Push(level));
        timer.Tick += (_, _) => Refresh();
        timer.Start();
        Refresh();
    }

    // MARK: - State

    private void Refresh()
    {
        PrepareModel();

        bool micAllowed = MicrophoneAllowed();
        microphone.Set(micAllowed, micAllowed ? "Fale para testar" : "O Windows está bloqueando o microfone para os apps da área de trabalho");
        microphoneTest.Visibility = micAllowed ? Visibility.Visible : Visibility.Collapsed;
        microphoneSettings.Visibility = micAllowed ? Visibility.Collapsed : Visibility.Visible;
        if (micAllowed && !metering) StartMeter();
        if (!micAllowed && metering) StopMeter();

        bool ready = TranscriptionReady(model);
        var (label, fraction) = Download();
        transcription.Set(ready, TranscriptionDetail(ready, label, fraction));
        progress.Visibility = fraction == null ? Visibility.Collapsed : Visibility.Visible;
        progress.Value = fraction ?? 0;
        chooseButton.Content = ready ? "Trocar" : "Escolher";

        bool allDone = micAllowed && ready;
        FooterText.Text = allDone ? "Tudo pronto." : "Dá para terminar depois em Ajustes e Modelos.";
        FinishButton.Content = allDone ? "Começar a usar" : "Fazer depois";
        FinishButton.Style = allDone ? (Style)FindResource("PrimaryButton") : null;
    }

    /// The whisper server and the chosen model are installed, or the chosen provider has a key.
    private static bool TranscriptionReady(AppModel model)
    {
        if (model.Engine == TranscriptionEngine.Cloud) return model.HasKey(model.TranscriptionProvider);
        model.Models.Refresh();
        return model.Models.WhisperInstalled && model.Models.Items.Any(i => i.Id == model.LocalModel && i.IsInstalled);
    }

    /// What is downloading for transcription and how far along: the whisper server first, then the model.
    private (string? Label, double? Fraction) Download()
    {
        if (model.Engine != TranscriptionEngine.Local) return (null, null);
        if (model.Models.WhisperProgress is double whisper) return ("o whisper", whisper);
        foreach (var id in new[] { model.LocalModel, Recommended })
        {
            var item = model.Models.Items.FirstOrDefault(i => i.Id == id);
            if (item?.Progress is double fraction) return ($"o {item.Name}", fraction);
        }
        return (null, null);
    }

    private string TranscriptionDetail(bool ready, string? label, double? fraction)
    {
        if (label != null && fraction is double value) return $"Baixando {label}… {value:P0}";
        if (model.Engine == TranscriptionEngine.Cloud)
        {
            var provider = model.TranscriptionProvider.Title();
            return ready ? $"{provider} · {model.TranscriptionModel}, com a sua chave"
                         : $"Falta a chave da {provider}: clique em Escolher";
        }
        if (ready && model.Models.Items.FirstOrDefault(i => i.Id == model.LocalModel) is { } selected)
            return $"Whisper {selected.Name} · no seu computador, grátis e offline";
        return model.Models.LastError ?? "Preparando…";
    }

    /// Without a usable model, downloads the recommended one by itself and uses it when it's ready. Someone who
    /// picked another model, or an API key, keeps their choice. The whisper server installs on launch.
    private void PrepareModel()
    {
        if (model.Engine != TranscriptionEngine.Local) return;
        var items = model.Models.Items;
        if (items.Any(i => i.Id == model.LocalModel && i.IsInstalled)) return;
        var recommended = items.First(i => i.Id == Recommended);
        if (recommended.IsInstalled) model.LocalModel = recommended.Id;
        else if (recommended.Progress == null) model.Models.Download(recommended);
    }

    /// Windows' privacy switches for the microphone: for all apps, and for desktop apps like this one.
    private static bool MicrophoneAllowed()
    {
        static bool Denied(RegistryKey root, string path)
        {
            using var key = root.OpenSubKey(path);
            return string.Equals(key?.GetValue("Value") as string, "Deny", StringComparison.OrdinalIgnoreCase);
        }
        return !Denied(Registry.LocalMachine, MicrophoneConsent)
            && !Denied(Registry.CurrentUser, MicrophoneConsent)
            && !Denied(Registry.CurrentUser, MicrophoneConsent + @"\NonPackaged");
    }

    // MARK: - Microphone test

    private void LoadMicrophones()
    {
        microphoneBox.Items.Clear();
        microphoneBox.Items.Add(new ComboBoxItem { Content = "Automático", Tag = Microphones.Automatic });
        var devices = Microphones.Inputs();
        foreach (var device in devices) microphoneBox.Items.Add(new ComboBoxItem { Content = device.Name, Tag = device.Id });
        if (model.Microphone != Microphones.Automatic && devices.All(d => d.Id != model.Microphone))
            microphoneBox.Items.Add(new ComboBoxItem { Content = "Microfone desconectado", Tag = model.Microphone });
        microphoneBox.SelectedItem = microphoneBox.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == model.Microphone);
    }

    /// Listens for the level bars only; what it records is dropped.
    private async void StartMeter()
    {
        if (metering) await meter.StopAsync();
        try
        {
            meter.Start();
            metering = true;
        }
        catch (Exception e)
        {
            metering = false;
            Log.Write("Onboarding microphone test: " + e.Message);
        }
    }

    private async void StopMeter()
    {
        if (!metering) return;
        metering = false;
        await meter.StopAsync();
        Array.Clear(levels);
        Draw();
    }

    private void Push(float level)
    {
        if (!metering) return;
        Array.Copy(levels, 1, levels, 0, levels.Length - 1);
        levels[^1] = level;
        Draw();
    }

    private void Draw()
    {
        for (int i = 0; i < bars.Length; i++) bars[i].Height = 3 + 15 * Loudness(levels[i]);
    }

    /// Decibels rather than raw RMS: a normal voice sits around -30 dBFS, which barely moves a linear bar.
    private static double Loudness(float rms)
    {
        double decibels = 20 * Math.Log10(Math.Max(rms, 1e-6));
        return Math.Clamp((decibels + 55) / 40, 0, 1);
    }

    // MARK: - Finish

    private void Finish_Click(object sender, RoutedEventArgs e)
    {
        model.OnboardingDone = true;
        Close();
    }

    /// Closing it early still opens the app; it comes back on the next launch until it's finished.
    protected override void OnClosed(EventArgs e)
    {
        timer.Stop();
        StopMeter();
        base.OnClosed(e);
        if (finished) return;
        finished = true;
        onFinish();
    }

    private static void Open(string uri)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true }); }
        catch (Exception e) { Log.Write("Open " + uri + ": " + e.Message); }
    }

    /// A checklist row: a check that turns green when done, a title and detail, and the actions on the right.
    private sealed class Row
    {
        private static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");
        private readonly TextBlock check = new() { FontFamily = Icons, FontSize = 20, VerticalAlignment = VerticalAlignment.Center, Width = 24 };
        private readonly TextBlock detail = new() { FontSize = 12, TextWrapping = TextWrapping.Wrap };

        public Row(string title, bool divider)
        {
            var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 12, 0) };
            text.Children.Add(new TextBlock { Text = title, FontSize = 14, FontWeight = FontWeights.SemiBold });
            detail.SetResourceReference(TextBlock.ForegroundProperty, "BrandSecondary");
            text.Children.Add(detail);
            var row = new DockPanel { Margin = new Thickness(16, 14, 16, 14) };
            DockPanel.SetDock(check, Dock.Left);
            row.Children.Add(check);
            DockPanel.SetDock(Trailing, Dock.Right);
            row.Children.Add(Trailing);
            row.Children.Add(text);
            Root = new Border { Child = row, BorderThickness = new Thickness(0, 0, 0, divider ? 1 : 0) };
            Root.SetResourceReference(Border.BorderBrushProperty, "BrandBorder");
        }

        public Border Root { get; }
        public StackPanel Trailing { get; } = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };

        public void Set(bool done, string text)
        {
            check.Text = done ? "" : "";
            if (done) check.Foreground = ReadyBrush();
            else check.SetResourceReference(TextBlock.ForegroundProperty, "BrandTertiary");
            detail.Text = text;
        }

        /// The same green as the Mac's "ready", a lighter one on dark backgrounds.
        private static Brush ReadyBrush()
        {
            bool dark = Application.Current.TryFindResource("BrandBackground") is SolidColorBrush { Color.R: < 0x80 };
            return Brand.Brush(dark ? 0x7FA88Au : 0x3F6B4Fu);
        }
    }
}
