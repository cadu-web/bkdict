using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Bkdict.Core;

/// One event of today ± 1 day, with an occurrence already expanded from its repetition.
public sealed record CalendarEvent(string Title, DateTimeOffset Start, DateTimeOffset End, List<string> Attendees);

/// The calendar behind an iCal (.ics) address pasted in Ajustes (docs/reunioes.md, "Fase 4"): fetched every
/// 15 minutes in the background, kept as the events of yesterday, today and tomorrow.
public static class IcsCalendar
{
    private static List<CalendarEvent> events = new();
    private static Timer? timer;
    private static readonly object Gate = new();

    /// Starts (or restarts, after the address changed) the background refresh.
    public static void Start()
    {
        timer?.Dispose();
        timer = new Timer(_ => _ = RefreshAsync(), null, TimeSpan.Zero, TimeSpan.FromMinutes(15));
    }

    public static async Task RefreshAsync()
    {
        var url = AppSettings.Current.CalendarIcsUrl?.Trim();
        if (string.IsNullOrEmpty(url))
        {
            lock (Gate) events = new();
            Changed?.Invoke();
            return;
        }
        // Google and Outlook hand out webcal:// links for the same https address.
        if (url.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) url = "https://" + url[9..];
        try
        {
            using var deadline = Http.Deadline(20);
            var text = await Http.Client.GetStringAsync(url, deadline.Token);
            var parsed = Parse(text, DateTimeOffset.Now);
            lock (Gate) events = parsed;
            Changed?.Invoke();
        }
        catch (Exception e)
        {
            Log.Write("calendar: " + e.Message);
        }
    }

    /// True when an iCal address is set (the Reuniões page shows "Conectar calendário" otherwise).
    public static bool IsConfigured => !string.IsNullOrWhiteSpace(AppSettings.Current.CalendarIcsUrl);

    /// Raised after each refresh, so the Reuniões page can show the day's events.
    public static event Action? Changed;

    /// Today's events (local day), in order of start.
    public static List<CalendarEvent> Today(DateTimeOffset now)
    {
        List<CalendarEvent> list;
        lock (Gate) list = events;
        var today = now.LocalDateTime.Date;
        return list.Where(e => e.Start.LocalDateTime.Date == today).OrderBy(e => e.Start).ToList();
    }

    /// The event happening now: started and not over, or starting within 10 minutes; the closest start wins.
    public static CalendarEvent? Current(DateTimeOffset now)
    {
        List<CalendarEvent> list;
        lock (Gate) list = events;
        return list.Where(e => e.Start <= now.AddMinutes(10) && e.End > now)
                   .OrderBy(e => Math.Abs((e.Start - now).TotalSeconds))
                   .FirstOrDefault();
    }

    // MARK: - Parsing

    /// The events of `around` ± 1 day (local calendar days), repetitions expanded.
    public static List<CalendarEvent> Parse(string ics, DateTimeOffset around)
    {
        var windowStart = new DateTimeOffset(around.LocalDateTime.Date.AddDays(-1), around.Offset);
        var windowEnd = windowStart.AddDays(3);
        var result = new List<CalendarEvent>();
        foreach (var block in Events(Unfold(ics)))
        {
            if (block.Get("STATUS")?.Value.Equals("CANCELLED", StringComparison.OrdinalIgnoreCase) == true) continue;
            if (block.Get("DTSTART") is not { } startLine || ParseDate(startLine) is not { } start) continue;
            var end = block.Get("DTEND") is { } endLine && ParseDate(endLine) is { } e ? e
                    : block.Get("DURATION") is { } duration && ParseDuration(duration.Value) is { } length ? start + length
                    : start.AddHours(startLine.Value.Length == 8 ? 24 : 1);
            var length2 = end - start;
            var title = Unescape(block.Get("SUMMARY")?.Value ?? "Reunião");
            var attendees = block.All("ATTENDEE").Concat(block.All("ORGANIZER")).Select(Person)
                .Where(name => name.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            var excluded = block.All("EXDATE").SelectMany(line =>
                line.Value.Split(',').Select(v => ParseDate(line with { Value = v }))).OfType<DateTimeOffset>().ToHashSet();

            foreach (var occurrence in Occurrences(start, block.Get("RRULE")?.Value, windowEnd))
            {
                if (excluded.Contains(occurrence)) continue;
                var occurrenceEnd = occurrence + length2;
                if (occurrenceEnd <= windowStart || occurrence >= windowEnd) continue;
                result.Add(new CalendarEvent(title, occurrence, occurrenceEnd, attendees));
            }
        }
        return result.OrderBy(e => e.Start).ToList();
    }

    private sealed record Line(string Name, Dictionary<string, string> Parameters, string Value);

    private sealed class Block
    {
        public readonly List<Line> Lines = new();
        public Line? Get(string name) => Lines.FirstOrDefault(l => l.Name == name);
        public IEnumerable<Line> All(string name) => Lines.Where(l => l.Name == name);
    }

    /// Joins folded lines (a line starting with a space or tab continues the previous one).
    private static List<string> Unfold(string ics)
    {
        var lines = new List<string>();
        foreach (var raw in ics.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            if ((raw.StartsWith(' ') || raw.StartsWith('\t')) && lines.Count > 0) lines[^1] += raw[1..];
            else if (raw.Length > 0) lines.Add(raw);
        }
        return lines;
    }

    private static IEnumerable<Block> Events(List<string> lines)
    {
        Block? current = null;
        foreach (var text in lines)
        {
            if (text == "BEGIN:VEVENT") { current = new Block(); continue; }
            if (text == "END:VEVENT") { if (current != null) yield return current; current = null; continue; }
            if (current == null) continue;
            // Nested blocks (VALARM) end with their own END; their lines are harmless but skipped by name.
            int colon = IndexOfValueColon(text);
            if (colon < 0) continue;
            var head = text[..colon].Split(';');
            var parameters = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var part in head.Skip(1))
            {
                int equals = part.IndexOf('=');
                if (equals > 0) parameters[part[..equals]] = part[(equals + 1)..].Trim('"');
            }
            current.Lines.Add(new Line(head[0].ToUpperInvariant(), parameters, text[(colon + 1)..]));
        }
    }

    /// The colon that starts the value, skipping colons inside quoted parameters (CN="Ana: Vendas").
    private static int IndexOfValueColon(string text)
    {
        bool quoted = false;
        for (int i = 0; i < text.Length; i++)
        {
            if (text[i] == '"') quoted = !quoted;
            else if (text[i] == ':' && !quoted) return i;
        }
        return -1;
    }

    /// A date-time: UTC (Z), in a named zone (TZID), floating (local) or a whole day.
    private static DateTimeOffset? ParseDate(Line line)
    {
        var value = line.Value.Trim();
        if (value.Length == 8 && DateTime.TryParseExact(value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day))
            return new DateTimeOffset(day, TimeZoneInfo.Local.GetUtcOffset(day));
        bool utc = value.EndsWith('Z');
        if (!DateTime.TryParseExact(value.TrimEnd('Z'), "yyyyMMdd'T'HHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var time))
            return null;
        if (utc) return new DateTimeOffset(DateTime.SpecifyKind(time, DateTimeKind.Utc));
        var zone = line.Parameters.TryGetValue("TZID", out var id) ? Zone(id) : TimeZoneInfo.Local;
        return new DateTimeOffset(time, zone.GetUtcOffset(time));
    }

    /// The zone by IANA id ("America/Sao_Paulo"), by Windows id, or the local one.
    private static TimeZoneInfo Zone(string id)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch { }
        try
        {
            if (TimeZoneInfo.TryConvertIanaIdToWindowsId(id, out var windows)) return TimeZoneInfo.FindSystemTimeZoneById(windows);
        }
        catch { }
        return TimeZoneInfo.Local;
    }

    /// "PT1H30M", "P1D", "-PT15M".
    private static TimeSpan? ParseDuration(string value)
    {
        var match = System.Text.RegularExpressions.Regex.Match(value.Trim(),
            @"^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$");
        if (!match.Success) return null;
        int Part(int index) => match.Groups[index].Success ? int.Parse(match.Groups[index].Value) : 0;
        var span = new TimeSpan(Part(2) * 7 + Part(3), Part(4), Part(5), Part(6));
        return match.Groups[1].Value == "-" ? -span : span;
    }

    /// The start of each occurrence up to `until`: the event itself, or its DAILY/WEEKLY repetition.
    private static IEnumerable<DateTimeOffset> Occurrences(DateTimeOffset start, string? rule, DateTimeOffset until)
    {
        if (string.IsNullOrEmpty(rule))
        {
            yield return start;
            yield break;
        }
        var parts = rule.Split(';').Select(p => p.Split('=', 2)).Where(p => p.Length == 2)
            .ToDictionary(p => p[0].ToUpperInvariant(), p => p[1], StringComparer.OrdinalIgnoreCase);
        var frequency = parts.GetValueOrDefault("FREQ", "").ToUpperInvariant();
        if (frequency != "DAILY" && frequency != "WEEKLY")
        {
            // Monthly and yearly repetitions are not expanded: only the first occurrence counts.
            yield return start;
            yield break;
        }
        int interval = int.TryParse(parts.GetValueOrDefault("INTERVAL"), out var i) && i > 0 ? i : 1;
        int? count = int.TryParse(parts.GetValueOrDefault("COUNT"), out var c) ? c : null;
        DateTimeOffset? last = parts.TryGetValue("UNTIL", out var untilText)
            ? ParseDate(new Line("UNTIL", new(), untilText)) : null;
        var days = parts.TryGetValue("BYDAY", out var byDay)
            ? byDay.Split(',').Select(d => DayOfWeekFrom(d[^2..])).OfType<DayOfWeek>().ToHashSet()
            : new HashSet<DayOfWeek> { start.DayOfWeek };

        // Walks day by day in the event's own clock, keeping its time of day and offset rule.
        var local = start.DateTime;
        var offsetZone = start.Offset;
        int produced = 0;
        for (var date = local.Date; ; date = date.AddDays(1))
        {
            var candidate = new DateTimeOffset(date + local.TimeOfDay, offsetZone);
            if (candidate > until || (last is { } l && candidate > l) || (count is { } n && produced >= n)) yield break;
            int dayIndex = (int)(date - local.Date).TotalDays;
            bool matches = frequency == "DAILY"
                ? dayIndex % interval == 0
                : days.Contains(date.DayOfWeek) && WeekIndex(local.Date, date) % interval == 0;
            if (!matches) continue;
            produced++;
            yield return candidate;
        }
    }

    /// Weeks between two dates, counting from the week (Monday-based) of the first.
    private static int WeekIndex(DateTime first, DateTime date)
    {
        static DateTime Monday(DateTime d) => d.AddDays(-(((int)d.DayOfWeek + 6) % 7));
        return (int)((Monday(date) - Monday(first)).TotalDays / 7);
    }

    private static DayOfWeek? DayOfWeekFrom(string code) => code.ToUpperInvariant() switch
    {
        "MO" => DayOfWeek.Monday, "TU" => DayOfWeek.Tuesday, "WE" => DayOfWeek.Wednesday, "TH" => DayOfWeek.Thursday,
        "FR" => DayOfWeek.Friday, "SA" => DayOfWeek.Saturday, "SU" => DayOfWeek.Sunday, _ => null,
    };

    /// The name of an attendee or organizer: CN, or the part of the e-mail before the @.
    private static string Person(Line line)
    {
        if (line.Parameters.TryGetValue("CN", out var name) && name.Trim().Length > 0) return Unescape(name.Trim());
        var mail = line.Value.Replace("mailto:", "", StringComparison.OrdinalIgnoreCase);
        int at = mail.IndexOf('@');
        return at > 0 ? mail[..at] : "";
    }

    private static string Unescape(string value) =>
        value.Replace("\\n", " ").Replace("\\N", " ").Replace("\\,", ",").Replace("\\;", ";").Replace("\\\\", "\\").Trim();
}
