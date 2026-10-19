using System;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using Bkdict.Core;

namespace Bkdict.UI;

public partial class MeetingsPage : UserControl
{
    private readonly AppModel model;
    private Meeting? selected;

    public MeetingsPage(AppModel model)
    {
        this.model = model;
        InitializeComponent();
        MeetingList.ItemsSource = model.Meetings;
        model.Meetings.CollectionChanged += (_, _) => UpdateEmpty();
        model.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppModel.IsMeetingRecording) or nameof(AppModel.MeetingElapsed)) UpdateRecording();
            if (e.PropertyName == nameof(AppModel.IsMeetingRecording))
            {
                // A new recording goes to the top of the list: show it.
                if (model.RecordingMeeting is { } meeting) MeetingList.SelectedItem = meeting;
                UpdateActions();
            }
        };
        UpdateRecording();
        UpdateEmpty();
        if (model.Meetings.Count > 0) MeetingList.SelectedIndex = 0;
    }

    private void UpdateRecording()
    {
        RecordButton.Content = model.IsMeetingRecording ? "Parar gravação" : "Gravar reunião";
        ElapsedText.Text = model.IsMeetingRecording ? "● " + Meeting.Clock(model.MeetingElapsed.TotalSeconds) : "";
    }

    private void UpdateEmpty()
    {
        bool empty = model.Meetings.Count == 0;
        EmptyText.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        Body.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        if (!empty && MeetingList.SelectedItem == null) MeetingList.SelectedIndex = 0;
    }

    private void MeetingList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (selected != null) selected.PropertyChanged -= Selected_PropertyChanged;
        selected = MeetingList.SelectedItem as Meeting;
        if (selected != null) selected.PropertyChanged += Selected_PropertyChanged;
        DeleteConfirm.Visibility = Visibility.Collapsed;
        RenderMeta();
        RenderBody();
    }

    private void Selected_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        Dispatcher.InvokeAsync(() =>
        {
            RenderMeta();
            if (e.PropertyName is nameof(Meeting.Segments) or nameof(Meeting.Summary) or nameof(Meeting.Status)) RenderBody();
        });
    }

    // MARK: - Detail

    private void RenderMeta()
    {
        Detail.Visibility = selected == null ? Visibility.Collapsed : Visibility.Visible;
        if (selected is not { } meeting) return;
        DetailTitle.Text = meeting.Title;
        DetailMeta.Text = $"{meeting.StartedAt.LocalDateTime:dd/MM/yyyy HH:mm} · {meeting.DurationLabel} · {meeting.StatusLabel}";
        MicOnlyBanner.Visibility = meeting.SystemAudio ? Visibility.Collapsed : Visibility.Visible;
        UpdateActions();
    }

    private void UpdateActions()
    {
        if (selected is not { } meeting) return;
        bool recording = meeting == model.RecordingMeeting;
        bool busy = recording || meeting.Status is Meeting.Recording or Meeting.Transcribing or Meeting.Summarizing;
        CopySummaryButton.IsEnabled = !string.IsNullOrWhiteSpace(meeting.Summary);
        CopyTranscriptButton.IsEnabled = meeting.Segments.Count > 0;
        ResummarizeButton.IsEnabled = !busy && meeting.Segments.Count > 0;
        DeleteButton.IsEnabled = !recording;
    }

    private void RenderBody()
    {
        SummaryPanel.Children.Clear();
        TranscriptPanel.Children.Clear();
        if (selected is not { } meeting) return;

        if (string.IsNullOrWhiteSpace(meeting.Summary))
        {
            SummaryPanel.Children.Add(Subtle(meeting.Status switch
            {
                Meeting.Recording => "O resumo sai quando você parar a gravação.",
                Meeting.Failed => "Sem resumo: a transcrição falhou.",
                _ => "Preparando o resumo…",
            }));
        }
        else
        {
            RenderMarkdown(meeting.Summary);
        }

        if (meeting.Segments.Count == 0)
        {
            TranscriptPanel.Children.Add(Subtle(meeting.Status switch
            {
                Meeting.Recording => "A transcrição sai quando você parar a gravação.",
                Meeting.Transcribing => "Transcrevendo…",
                Meeting.Failed => "A transcrição falhou: " + (meeting.Error ?? "erro desconhecido"),
                _ => "Ninguém falou nesta gravação.",
            }));
            return;
        }
        var mono = (FontFamily)FindResource("MonoFont");
        foreach (var segment in meeting.Segments)
        {
            var line = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 6) };
            line.Inlines.Add(new Run("[" + Meeting.Clock(segment.Start) + "] ")
            {
                FontFamily = mono, FontSize = 12, Foreground = (Brush)FindResource("BrandTertiary"),
            });
            line.Inlines.Add(new Run(segment.SpeakerLabel + ": ") { FontWeight = FontWeights.SemiBold });
            line.Inlines.Add(new Run(segment.Text));
            TranscriptPanel.Children.Add(line);
        }
    }

    /// Just enough Markdown for the summary: "## " headings, "- " bullets, plain paragraphs.
    private void RenderMarkdown(string markdown)
    {
        foreach (var raw in markdown.Split('\n'))
        {
            var line = raw.TrimEnd('\r').Trim();
            if (line.Length == 0) continue;
            if (line.StartsWith('#'))
            {
                SummaryPanel.Children.Add(new TextBlock
                {
                    Text = line.TrimStart('#').Trim(), FontSize = 15, FontWeight = FontWeights.SemiBold,
                    Margin = new Thickness(0, SummaryPanel.Children.Count == 0 ? 0 : 12, 0, 4), TextWrapping = TextWrapping.Wrap,
                });
            }
            else if (line.StartsWith("- ") || line.StartsWith("* "))
            {
                var bullet = new DockPanel { Margin = new Thickness(0, 0, 0, 3) };
                var mark = new TextBlock { Text = "•", Width = 14, Foreground = (Brush)FindResource("BrandAccent") };
                DockPanel.SetDock(mark, Dock.Left);
                bullet.Children.Add(mark);
                bullet.Children.Add(new TextBlock { Text = line[2..].Replace("**", ""), TextWrapping = TextWrapping.Wrap });
                SummaryPanel.Children.Add(bullet);
            }
            else
            {
                SummaryPanel.Children.Add(new TextBlock
                {
                    Text = line.Replace("**", ""), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 4),
                });
            }
        }
    }

    private static TextBlock Subtle(string text) => new()
    {
        Text = text, TextWrapping = TextWrapping.Wrap, Style = (Style)Application.Current.FindResource("Subtle"),
    };

    // MARK: - Actions

    private void Record_Click(object sender, RoutedEventArgs e) => model.ToggleMeeting?.Invoke();

    private void CopySummary_Click(object sender, RoutedEventArgs e) => Copy(selected?.Summary);

    private void CopyTranscript_Click(object sender, RoutedEventArgs e) => Copy(selected?.TranscriptText());

    private static void Copy(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        try { Clipboard.SetText(text); } catch (Exception e) { Log.Write("Copy meeting: " + e.Message); }
    }

    private void Resummarize_Click(object sender, RoutedEventArgs e)
    {
        if (selected != null) model.ResummarizeMeeting?.Invoke(selected);
    }

    private void Delete_Click(object sender, RoutedEventArgs e) => DeleteConfirm.Visibility = Visibility.Visible;

    private void CancelDelete_Click(object sender, RoutedEventArgs e) => DeleteConfirm.Visibility = Visibility.Collapsed;

    private void ConfirmDelete_Click(object sender, RoutedEventArgs e)
    {
        DeleteConfirm.Visibility = Visibility.Collapsed;
        if (selected is { } meeting) model.DeleteMeeting(meeting);
        if (model.Meetings.Count > 0) MeetingList.SelectedIndex = 0;
    }
}
