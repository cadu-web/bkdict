using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace Bkdict.Core;

/// One calendar event of yesterday, today or tomorrow.
public sealed record CalendarEvent(string Title, DateTimeOffset Start, DateTimeOffset End, List<string> Attendees, string? Link);

/// Google Calendar connected straight from the app, the desktop OAuth way (docs/reunioes.md, "Calendário — Google
/// Agenda"): authorization code with PKCE and a loopback redirect, the refresh token in the Credential Manager, the
/// events read from the Calendar API every 5 minutes. No server in between.
public static class GoogleCalendar
{
    private const string CredentialName = "google-calendar";
    private const string Scope = "openid email https://www.googleapis.com/auth/calendar.readonly";

    private static readonly object Gate = new();
    private static List<CalendarEvent> events = new();
    private static string? accessToken;
    private static DateTimeOffset accessExpires;
    private static DispatcherTimer? timer;

    private sealed record Credential(string ClientId, string ClientSecret);

    /// Raised when the connection or the events change, so Ajustes and the Reuniões page can redraw.
    public static event Action? Changed;

    public static bool IsConnecting { get; private set; }
    public static string? LastError { get; private set; }

    /// Connected: a refresh token is stored.
    public static bool IsConfigured => Credentials.Get(CredentialName) != null;

    public static string? Email => AppSettings.Current.GoogleEmail;

    /// The OAuth client registered in BKDG's Google Cloud, shipped in Resources/google-oauth.json.
    private static Credential? Config
    {
        get
        {
            try
            {
                using var stream = typeof(GoogleCalendar).Assembly.GetManifestResourceStream("google-oauth.json");
                if (stream == null) return null;
                using var reader = new StreamReader(stream);
                var json = JsonHelpers.Parse(reader.ReadToEnd());
                var id = JsonHelpers.String(() => json?["clientId"]);
                var secret = JsonHelpers.String(() => json?["clientSecret"]);
                return string.IsNullOrWhiteSpace(id) ? null : new Credential(id, secret ?? "");
            }
            catch
            {
                return null;
            }
        }
    }

    /// Starts the 5-minute refresh (call once, on the UI thread).
    public static void Start()
    {
        timer ??= new DispatcherTimer { Interval = TimeSpan.FromMinutes(5) };
        timer.Tick += (_, _) => _ = RefreshAsync();
        timer.Start();
        _ = RefreshAsync();
    }

    // MARK: - Connect

    public static async Task ConnectAsync()
    {
        if (IsConnecting) return;
        var config = Config;
        if (config == null)
        {
            LastError = "A credencial do Google ainda não foi configurada.";
            Changed?.Invoke();
            return;
        }
        IsConnecting = true;
        LastError = null;
        Changed?.Invoke();
        try
        {
            var verifier = RandomUrlSafe(64);
            var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
            var state = RandomUrlSafe(24);
            var port = FreePort();
            var redirect = $"http://127.0.0.1:{port}/";

            using var listener = new HttpListener();
            listener.Prefixes.Add(redirect);
            listener.Start();

            var authorize = "https://accounts.google.com/o/oauth2/v2/auth?" + Form(new()
            {
                ["client_id"] = config.ClientId,
                ["redirect_uri"] = redirect,
                ["response_type"] = "code",
                ["scope"] = Scope,
                ["access_type"] = "offline",
                ["prompt"] = "consent",
                ["code_challenge"] = challenge,
                ["code_challenge_method"] = "S256",
                ["state"] = state,
            });
            Process.Start(new ProcessStartInfo(authorize) { UseShellExecute = true })?.Dispose();

            var code = await WaitForCodeAsync(listener, state);

            using var deadline = Http.Deadline(30);
            using var response = await Http.Client.PostAsync("https://oauth2.googleapis.com/token",
                new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["code"] = code,
                    ["client_id"] = config.ClientId,
                    ["client_secret"] = config.ClientSecret,
                    ["redirect_uri"] = redirect,
                    ["grant_type"] = "authorization_code",
                    ["code_verifier"] = verifier,
                }), deadline.Token);
            var json = JsonHelpers.Parse(await response.Content.ReadAsStringAsync(deadline.Token));
            var refresh = JsonHelpers.String(() => json?["refresh_token"]);
            if (!response.IsSuccessStatusCode || refresh == null)
                throw new UserFacingException("o Google não devolveu o acesso (" + (JsonHelpers.String(() => json?["error"]) ?? $"{(int)response.StatusCode}") + ")");

            Credentials.Set(CredentialName, refresh);
            Remember(json);
            AppSettings.Current.GoogleEmail = EmailFrom(JsonHelpers.String(() => json?["id_token"]));
            AppSettings.Current.Save();
            await RefreshAsync();
        }
        catch (Exception e)
        {
            LastError = "Não foi possível conectar: " + (e is UserFacingException ? e.Message : e.Message.TrimEnd('.'));
            Log.Write("google connect: " + e);
        }
        finally
        {
            IsConnecting = false;
            Changed?.Invoke();
        }
    }

    /// Waits for Google's redirect (up to 3 minutes) and answers it with a short page.
    private static async Task<string> WaitForCodeAsync(HttpListener listener, string state)
    {
        using var cancel = new CancellationTokenSource(TimeSpan.FromMinutes(3));
        while (true)
        {
            var pending = listener.GetContextAsync();
            var finished = await Task.WhenAny(pending, Task.Delay(Timeout.Infinite, cancel.Token)).ConfigureAwait(false);
            if (finished != pending) throw new UserFacingException("o tempo para entrar no Google acabou");
            var context = await pending;
            var query = context.Request.QueryString;
            var error = query["error"];
            var code = query["code"];
            var ok = error == null && code != null && query["state"] == state;
            if (error == null && code == null)
            {
                // Something else (a favicon request): not the redirect.
                context.Response.StatusCode = 404;
                context.Response.Close();
                continue;
            }
            await Reply(context.Response, ok);
            if (error != null) throw new UserFacingException(error == "access_denied" ? "o acesso foi negado" : error);
            if (!ok) throw new UserFacingException("a resposta do Google não confere");
            return code!;
        }
    }

    private static async Task Reply(HttpListenerResponse response, bool ok)
    {
        var message = ok ? "Pronto, pode voltar ao Bkdict." : "Não foi possível conectar. Volte ao Bkdict e tente de novo.";
        var html = "<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\"><title>Bkdict</title></head>" +
                   "<body style=\"margin:0;height:100vh;display:flex;align-items:center;justify-content:center;" +
                   "background:#0A0A0A;color:#F1ECE2;font-family:'IBM Plex Sans','Segoe UI',sans-serif;font-size:18px\">" +
                   $"<p>{message}</p></body></html>";
        var bytes = Encoding.UTF8.GetBytes(html);
        response.ContentType = "text/html; charset=utf-8";
        response.ContentLength64 = bytes.Length;
        await response.OutputStream.WriteAsync(bytes);
        response.Close();
    }

    public static async Task DisconnectAsync()
    {
        var token = Credentials.Get(CredentialName);
        if (token != null)
        {
            try
            {
                using var deadline = Http.Deadline(10);
                using var _ = await Http.Client.PostAsync("https://oauth2.googleapis.com/revoke",
                    new FormUrlEncodedContent(new Dictionary<string, string> { ["token"] = token }), deadline.Token);
            }
            catch (Exception e)
            {
                Log.Write("google revoke: " + e.Message);
            }
        }
        Credentials.Set(CredentialName, null);
        AppSettings.Current.GoogleEmail = null;
        AppSettings.Current.Save();
        lock (Gate)
        {
            accessToken = null;
            events = new();
        }
        LastError = null;
        Changed?.Invoke();
    }

    // MARK: - Events

    public static async Task RefreshAsync()
    {
        if (!IsConfigured) return;
        try
        {
            var token = await AccessTokenAsync();
            var day = DateTimeOffset.Now.Date;
            var from = new DateTimeOffset(day.AddDays(-1));
            var to = new DateTimeOffset(day.AddDays(2));
            var url = "https://www.googleapis.com/calendar/v3/calendars/primary/events?" + Form(new()
            {
                ["timeMin"] = from.ToString("yyyy-MM-dd'T'HH:mm:sszzz"),
                ["timeMax"] = to.ToString("yyyy-MM-dd'T'HH:mm:sszzz"),
                ["singleEvents"] = "true",
                ["orderBy"] = "startTime",
                ["maxResults"] = "100",
            });
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
            using var deadline = Http.Deadline(20);
            using var response = await Http.Client.SendAsync(request, deadline.Token);
            var body = await response.Content.ReadAsStringAsync(deadline.Token);
            if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"calendar {(int)response.StatusCode}: {body}");
            var parsed = Parse(JsonHelpers.Parse(body));
            lock (Gate) events = parsed;
            LastError = null;
        }
        catch (Exception e)
        {
            Log.Write("google calendar: " + e.Message);
        }
        Changed?.Invoke();
    }

    /// Items of the Calendar API: not cancelled, not all-day; attendees without the person and without rooms.
    private static List<CalendarEvent> Parse(JsonNode? json)
    {
        var result = new List<CalendarEvent>();
        if (json?["items"] is not JsonArray items) return result;
        foreach (var item in items)
        {
            if (JsonHelpers.String(() => item?["status"]) == "cancelled") continue;
            var start = JsonHelpers.String(() => item?["start"]?["dateTime"]);
            var end = JsonHelpers.String(() => item?["end"]?["dateTime"]);
            if (start == null || end == null) continue; // all-day events carry only "date"
            if (!DateTimeOffset.TryParse(start, out var startAt) || !DateTimeOffset.TryParse(end, out var endAt)) continue;

            var attendees = new List<string>();
            if (item?["attendees"] is JsonArray people)
            {
                foreach (var person in people)
                {
                    if (Bool(person?["self"]) || Bool(person?["resource"])) continue;
                    var name = JsonHelpers.String(() => person?["displayName"]);
                    if (string.IsNullOrWhiteSpace(name))
                        name = JsonHelpers.String(() => person?["email"])?.Split('@')[0];
                    if (!string.IsNullOrWhiteSpace(name) && !attendees.Contains(name, StringComparer.OrdinalIgnoreCase))
                        attendees.Add(name);
                }
            }

            var link = JsonHelpers.String(() => item?["hangoutLink"]);
            if (link == null && item?["conferenceData"]?["entryPoints"] is JsonArray entries)
            {
                link = entries.Where(entry => JsonHelpers.String(() => entry?["entryPointType"]) == "video")
                              .Select(entry => JsonHelpers.String(() => entry?["uri"]))
                              .FirstOrDefault(uri => uri != null);
            }

            var title = JsonHelpers.String(() => item?["summary"]);
            result.Add(new CalendarEvent(string.IsNullOrWhiteSpace(title) ? "Reunião" : title, startAt, endAt, attendees, link));
        }
        return result;
    }

    private static bool Bool(JsonNode? node)
    {
        try { return node is JsonValue value && value.TryGetValue(out bool flag) && flag; }
        catch { return false; }
    }

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

    // MARK: - Tokens

    /// The access token in memory, renewed with the stored refresh token when it is about to expire.
    private static async Task<string> AccessTokenAsync()
    {
        lock (Gate)
        {
            if (accessToken != null && DateTimeOffset.Now < accessExpires) return accessToken;
        }
        var config = Config ?? throw new InvalidOperationException("sem credencial do Google");
        var refresh = Credentials.Get(CredentialName) ?? throw new InvalidOperationException("não conectado");
        using var deadline = Http.Deadline(20);
        using var response = await Http.Client.PostAsync("https://oauth2.googleapis.com/token",
            new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = config.ClientId,
                ["client_secret"] = config.ClientSecret,
                ["refresh_token"] = refresh,
                ["grant_type"] = "refresh_token",
            }), deadline.Token);
        var json = JsonHelpers.Parse(await response.Content.ReadAsStringAsync(deadline.Token));
        if (!response.IsSuccessStatusCode)
        {
            // A revoked or expired authorization: the person has to connect again.
            if (JsonHelpers.String(() => json?["error"]) == "invalid_grant")
            {
                Credentials.Set(CredentialName, null);
                LastError = "A conexão com o Google expirou. Conecte de novo.";
            }
            throw new InvalidOperationException($"token {(int)response.StatusCode}");
        }
        return Remember(json);
    }

    private static string Remember(JsonNode? json)
    {
        var token = JsonHelpers.String(() => json?["access_token"]) ?? throw new InvalidOperationException("sem access_token");
        double seconds = 3600;
        try { if (json?["expires_in"] is JsonValue value && value.TryGetValue(out double parsed)) seconds = parsed; } catch { }
        lock (Gate)
        {
            accessToken = token;
            accessExpires = DateTimeOffset.Now.AddSeconds(Math.Max(60, seconds - 60));
        }
        return token;
    }

    /// The e-mail in the ID token's payload (base64url JSON).
    private static string? EmailFrom(string? idToken)
    {
        var parts = idToken?.Split('.');
        if (parts == null || parts.Length < 2) return null;
        try
        {
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            var json = JsonHelpers.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(payload)));
            return JsonHelpers.String(() => json?["email"]);
        }
        catch
        {
            return null;
        }
    }

    // MARK: - Helpers

    private static int FreePort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    private static string RandomUrlSafe(int length)
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
        var bytes = RandomNumberGenerator.GetBytes(length);
        return new string(bytes.Select(b => alphabet[b % alphabet.Length]).ToArray());
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static string Form(Dictionary<string, string> values) =>
        string.Join("&", values.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
}
