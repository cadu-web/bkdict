using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Bkdict.Core;

/// One stretch of speech in a meeting: "me" is the microphone, "them" the system audio (docs/reunioes.md).
public sealed class MeetingSegment
{
    public string Source { get; set; } = "me";
    public double Start { get; set; }
    public double End { get; set; }
    public string Text { get; set; } = "";

    [JsonIgnore] public string SpeakerLabel => Source == "them" ? "Eles" : "Você";
}

/// A recorded meeting and its transcript, saved as meeting.json next to mic.wav and system.wav.
public sealed class Meeting : ObservableObject
{
    public const string Recording = "recording", Transcribing = "transcribing", Summarizing = "summarizing",
                        Ready = "ready", Failed = "failed";

    private string status = Recording;
    private double progress;
    private string? error;
    private double duration;
    private string? summary;
    private List<MeetingSegment> segments = new();
    private bool systemAudio = true;

    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    /// The call app it was recorded from, when started from a detected call ("Zoom", "Google Meet"…).
    public string? App { get; set; }
    public DateTimeOffset StartedAt { get; set; }

    public double Duration
    {
        get => duration;
        set { if (SetField(ref duration, value)) OnPropertyChanged(nameof(DurationLabel)); }
    }

    public bool SystemAudio
    {
        get => systemAudio;
        set { if (SetField(ref systemAudio, value)) OnPropertyChanged(nameof(StatusLabel)); }
    }

    public string Status
    {
        get => status;
        set { if (SetField(ref status, value)) OnPropertyChanged(nameof(StatusLabel)); }
    }

    public double Progress
    {
        get => progress;
        set { if (SetField(ref progress, value)) OnPropertyChanged(nameof(StatusLabel)); }
    }

    public string? Error
    {
        get => error;
        set { if (SetField(ref error, value)) OnPropertyChanged(nameof(StatusLabel)); }
    }

    public List<MeetingSegment> Segments
    {
        get => segments;
        set => SetField(ref segments, value);
    }

    public string? Summary
    {
        get => summary;
        set => SetField(ref summary, value);
    }

    [JsonIgnore] public string Folder => Path.Combine(Paths.Meetings, Id);
    [JsonIgnore] public string MicPath => Path.Combine(Folder, "mic.wav");
    [JsonIgnore] public string SystemPath => Path.Combine(Folder, "system.wav");

    [JsonIgnore]
    public string StatusLabel => status switch
    {
        Recording => "Gravando",
        Transcribing => $"Transcrevendo {(int)Math.Round(progress * 100)}%",
        Summarizing => "Resumindo",
        Failed => "Falhou: " + (error ?? "erro desconhecido"),
        _ => systemAudio ? "Pronta" : "Só o seu microfone",
    };

    [JsonIgnore] public string DurationLabel => Clock(duration);

    /// "mm:ss", or "h:mm:ss" from one hour on.
    public static string Clock(double seconds)
    {
        var time = TimeSpan.FromSeconds(Math.Max(0, Math.Floor(seconds)));
        return time.TotalHours >= 1 ? $"{(int)time.TotalHours}:{time.Minutes:00}:{time.Seconds:00}" : $"{time.Minutes:00}:{time.Seconds:00}";
    }

    /// The transcript as "[mm:ss] Você|Eles: texto", one segment per line: what is copied and what the summary reads.
    public string TranscriptText()
    {
        var builder = new StringBuilder();
        foreach (var segment in segments)
        {
            builder.Append('[').Append(Clock(segment.Start)).Append("] ").Append(segment.SpeakerLabel).Append(": ")
                   .AppendLine(segment.Text);
        }
        return builder.ToString().TrimEnd();
    }

    public static Meeting New(DateTimeOffset now, string? app = null) => new()
    {
        Id = now.ToString("yyyy-MM-dd_HH-mm-ss"),
        Title = app == null ? $"Reunião de {now:dd/MM}, {now:HH:mm}" : $"{app} · {now:dd/MM}, {now:HH:mm}",
        App = app,
        StartedAt = now,
    };
}

/// The meetings on disk: %LOCALAPPDATA%\Bkdict\meetings\<id>\meeting.json.
public static class MeetingStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public static List<Meeting> LoadAll()
    {
        var meetings = new List<Meeting>();
        foreach (var folder in Directory.EnumerateDirectories(Paths.Meetings))
        {
            var file = Path.Combine(folder, "meeting.json");
            if (!File.Exists(file)) continue;
            try
            {
                if (JsonSerializer.Deserialize<Meeting>(File.ReadAllBytes(file), Options) is { } meeting) meetings.Add(meeting);
            }
            catch (Exception e)
            {
                Log.Write($"Meeting {Path.GetFileName(folder)}: {e.Message}");
            }
        }
        return meetings.OrderByDescending(m => m.StartedAt).ToList();
    }

    public static void Save(Meeting meeting)
    {
        try
        {
            Directory.CreateDirectory(meeting.Folder);
            DataFile.WriteAtomic(Path.Combine(meeting.Folder, "meeting.json"), JsonSerializer.SerializeToUtf8Bytes(meeting, Options));
        }
        catch (Exception e)
        {
            Log.Write($"Meeting {meeting.Id} save: {e.Message}");
        }
    }

    public static void Delete(Meeting meeting)
    {
        try
        {
            if (Directory.Exists(meeting.Folder)) Directory.Delete(meeting.Folder, recursive: true);
        }
        catch (Exception e)
        {
            Log.Write($"Meeting {meeting.Id} delete: {e.Message}");
        }
    }
}
