using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Bkdict.Platform;

namespace Bkdict.Core;

/// Turns a recorded meeting into a transcript and a summary (docs/reunioes.md): speech segments of each track,
/// transcribed in time order with the dictation engine, echo removed, dictionary corrections, then the summary.
/// Runs one meeting at a time; every step saves meeting.json, so a restart resumes where it was.
public sealed class MeetingProcessor
{
    private readonly Func<byte[], Task<string>> transcribe;
    private readonly Func<string, string> correct;
    private readonly System.Threading.SemaphoreSlim queue = new(1, 1);

    /// `transcribe` takes a 16 kHz WAV and returns its text (the same path as a dictation, with the dictionary
    /// hint); `correct` applies the dictionary replacements.
    public MeetingProcessor(Func<byte[], Task<string>> transcribe, Func<string, string> correct)
    {
        this.transcribe = transcribe;
        this.correct = correct;
    }

    public async Task ProcessAsync(Meeting meeting)
    {
        await queue.WaitAsync();
        try
        {
            await TranscribeAsync(meeting);
            await SummarizeAsync(meeting);
        }
        catch (Exception e)
        {
            meeting.Status = Meeting.Failed;
            meeting.Error = e is UserFacingException ? e.Message : "não foi possível transcrever";
            Log.Write($"Meeting {meeting.Id}: {e}");
        }
        finally
        {
            MeetingStore.Save(meeting);
            queue.Release();
        }
    }

    /// Writes the summary again from the transcript, e.g. after configuring the AI.
    public async Task ResummarizeAsync(Meeting meeting)
    {
        await queue.WaitAsync();
        try
        {
            await SummarizeAsync(meeting);
        }
        finally
        {
            MeetingStore.Save(meeting);
            queue.Release();
        }
    }

    private async Task TranscribeAsync(Meeting meeting)
    {
        meeting.Status = Meeting.Transcribing;
        meeting.Progress = 0;
        meeting.Error = null;
        MeetingStore.Save(meeting);

        var tracks = new List<(string Source, MeetingTrack Track)>();
        if (File.Exists(meeting.MicPath)) tracks.Add(("me", new MeetingTrack(meeting.MicPath)));
        if (meeting.SystemAudio && File.Exists(meeting.SystemPath)) tracks.Add(("them", new MeetingTrack(meeting.SystemPath)));
        if (tracks.Count == 0) throw new UserFacingException("a gravação não tem áudio");

        var pending = new List<(string Source, MeetingTrack Track, double Start, double End)>();
        foreach (var (source, track) in tracks)
        {
            var levels = await Task.Run(track.WindowLevels);
            foreach (var (start, end) in MeetingTranscript.DetectSpeech(levels, track.Duration))
                pending.Add((source, track, start, end));
        }
        pending = pending.OrderBy(p => p.Start).ToList();

        var segments = new List<MeetingSegment>();
        for (int i = 0; i < pending.Count; i++)
        {
            var (source, track, start, end) = pending[i];
            var samples = await Task.Run(() => track.Read(start, end));
            var text = (await transcribe(AudioRecorder.Wav(samples))).Trim();
            if (text.Length > 0) segments.Add(new MeetingSegment { Source = source, Start = start, End = end, Text = text });
            meeting.Progress = (double)(i + 1) / pending.Count;
            if (i % 10 == 9) MeetingStore.Save(meeting);
        }

        meeting.Segments = MeetingTranscript.RemoveEcho(segments)
            .Select(s => { s.Text = correct(s.Text).Trim(); return s; })
            .Where(s => s.Text.Length > 0)
            .OrderBy(s => s.Start)
            .ToList();
        meeting.Progress = 1;
    }

    private async Task SummarizeAsync(Meeting meeting)
    {
        meeting.Status = Meeting.Summarizing;
        MeetingStore.Save(meeting);
        var transcript = meeting.TranscriptText();
        if (transcript.Length == 0)
        {
            meeting.Summary = "## Resumo\nNada foi dito nesta gravação.";
        }
        else
        {
            try
            {
                meeting.Summary = await Llm.SummarizeMeetingAsync(transcript);
            }
            catch (Exception e)
            {
                // Without an AI the meeting is still useful: the transcript stays, the summary says what to do.
                var reason = e is UserFacingException ? e.Message : "a IA não respondeu";
                meeting.Summary = $"## Resumo\nO resumo não foi gerado ({reason}). Configure a IA em Modelos e use Refazer resumo.";
                Log.Write($"Meeting {meeting.Id} summary: {e.Message}");
            }
        }
        meeting.Status = Meeting.Ready;
    }
}
