using System;
using System.Net.Http;
using System.Reflection;
using System.Threading.Tasks;

namespace Bkdict.Core;

/// Checks GitHub for a newer release. Windows has no in-place updater yet: the tray points to the download.
public static class Updater
{
    private const string LatestRelease = "https://api.github.com/repos/cadu-web/bkdict/releases/latest";

    public sealed record Release(Version Version, string Url);

    /// The newest release when it is newer than this build; null otherwise, and on any failure
    /// (offline, rate limit, or the repository still private).
    public static async Task<Release?> CheckAsync()
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, LatestRelease);
            request.Headers.UserAgent.ParseAdd("BKDict");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var deadline = Http.Deadline(10);
            using var response = await Http.Client.SendAsync(request, deadline.Token);
            if (!response.IsSuccessStatusCode) return null;
            var json = JsonHelpers.Parse(await response.Content.ReadAsStringAsync(deadline.Token));
            var tag = JsonHelpers.String(() => json?["tag_name"]);
            var url = JsonHelpers.String(() => json?["html_url"]);
            if (tag == null || url == null || !Version.TryParse(tag.TrimStart('v'), out var latest)) return null;
            // The assembly version has four parts (0.1.0.0); compare the three a release tag carries.
            var current = Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);
            var ours = new Version(current.Major, current.Minor, Math.Max(current.Build, 0));
            var theirs = new Version(latest.Major, latest.Minor, Math.Max(latest.Build, 0));
            return theirs > ours ? new Release(theirs, url) : null;
        }
        catch (Exception e)
        {
            Log.Write("update check: " + e.Message);
            return null;
        }
    }
}
