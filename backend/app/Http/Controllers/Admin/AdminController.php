<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AdminAuditLog;
use App\Models\AnalyticsEvent;
use App\Models\Announcement;
use App\Models\AppRelease;
use App\Models\FeedbackReport;
use App\Models\M3uSource;
use App\Models\M3uSourceVersion;
use App\Models\User;
use App\Models\UserDevice;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\View\View;

class AdminController extends Controller
{
    public function showLogin(Request $request): View|RedirectResponse
    {
        if (Auth::check() && Auth::user()?->isAdmin()) {
            return redirect()->route('admin.dashboard');
        }
        $a = random_int(1, 15);
        $b = random_int(1, 15);
        $request->session()->put('admin_captcha_answer', $a + $b);

        return view('admin.login', [
            'captchaQuestion' => "$a + $b",
        ]);
    }

    public function login(Request $request): RedirectResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'captcha' => ['required', 'integer'],
        ]);

        $expectedCaptcha = $request->session()->pull('admin_captcha_answer');
        if ($expectedCaptcha === null || (int) $credentials['captcha'] !== (int) $expectedCaptcha) {
            return back()
                ->withErrors(['captcha' => 'Jawaban captcha keamanan tidak sesuai.'])
                ->onlyInput('email');
        }

        if (!Auth::attempt([
            'email' => strtolower($credentials['email']),
            'password' => $credentials['password'],
            'is_active' => true,
        ])) {
            return back()->withErrors(['email' => 'Kredensial admin tidak valid.'])->onlyInput('email');
        }

        $user = Auth::user();
        if (!$user || !$user->isAdmin()) {
            Auth::logout();
            return back()->withErrors(['email' => 'Akun ini tidak memiliki akses admin.']);
        }

        $request->session()->regenerate();
        $this->audit($user, 'admin_login', 'user', (string) $user->id);

        return redirect()->route('admin.dashboard');
    }

    public function logout(Request $request): RedirectResponse
    {
        $user = Auth::user();
        if ($user) {
            $this->audit($user, 'admin_logout', 'user', (string) $user->id);
        }
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        return redirect()->route('admin.login');
    }

    public function dashboard(Request $request): View
    {
        $user = $request->user();
        $announcements = Announcement::orderBy('sort_order')->orderByDesc('updated_at')->get();
        $releases = AppRelease::orderByDesc('build_number')->orderBy('platform')->get();
        $m3uSources = M3uSource::with('versions')->orderByDesc('updated_at')->get();
        $feedbacks = FeedbackReport::orderByDesc('created_at')->limit(50)->get();
        $auditLogs = AdminAuditLog::with('adminUser')->orderByDesc('created_at')->limit(30)->get();
        $users = $user->role === User::ROLE_SUPER_ADMIN
            ? User::orderByDesc('created_at')->limit(50)->get()
            : collect();

        $recentPropsEvents = AnalyticsEvent::whereNotNull('properties')
            ->orderByDesc('occurred_at')
            ->limit(1000)
            ->get(['event_name', 'properties']);

        $totalDurationSeconds = 0;
        $durationSamples = 0;
        $searchCounts = [];
        $playlistCounts = [];
        $channelCounts = [];
        $playerErrorCounts = [];
        $syncFailureCounts = [];

        foreach ($recentPropsEvents as $ev) {
            $props = $ev->properties;
            if (!is_array($props)) {
                continue;
            }
            $sec = $props['duration_seconds'] ?? null;
            if (is_numeric($sec) && (float) $sec > 0 && (float) $sec <= 86400) {
                $totalDurationSeconds += (int) round((float) $sec);
                $durationSamples++;
            } elseif (isset($props['duration_ms']) && is_numeric($props['duration_ms']) && (float) $props['duration_ms'] > 0 && (float) $props['duration_ms'] <= 86400000) {
                $totalDurationSeconds += (int) round(((float) $props['duration_ms']) / 1000);
                $durationSamples++;
            }

            if ($ev->event_name === 'catalog_searched' && !empty($props['query_term'])) {
                $term = strtolower(trim((string) $props['query_term']));
                if ($term !== '') {
                    $searchCounts[$term] = ($searchCounts[$term] ?? 0) + 1;
                }
            } elseif ($ev->event_name === 'playlist_opened' && !empty($props['catalog_name'])) {
                $name = trim((string) $props['catalog_name']);
                $playlistCounts[$name] = ($playlistCounts[$name] ?? 0) + 1;
            } elseif ($ev->event_name === 'channel_opened' && !empty($props['channel_name'])) {
                $ch = trim((string) $props['channel_name']);
                $channelCounts[$ch] = ($channelCounts[$ch] ?? 0) + 1;
            } elseif ($ev->event_name === 'playback_error') {
                $code = trim((string) ($props['error_code'] ?? 'UNKNOWN_ERROR'));
                $playerErrorCounts[$code] = ($playerErrorCounts[$code] ?? 0) + 1;
            } elseif ($ev->event_name === 'sync_failed') {
                $target = trim((string) ($props['sync_target'] ?? 'unknown'));
                $syncFailureCounts[$target] = ($syncFailureCounts[$target] ?? 0) + 1;
            }
        }

        arsort($searchCounts);
        arsort($playlistCounts);
        arsort($channelCounts);
        arsort($playerErrorCounts);
        arsort($syncFailureCounts);

        $dailyRows = AnalyticsEvent::where('occurred_at', '>=', now()->subDays(6)->startOfDay())
            ->get(['installation_id', 'occurred_at']);
        $dailyBuckets = [];
        for ($i = 6; $i >= 0; $i--) {
            $d = now()->subDays($i)->format('Y-m-d');
            $dailyBuckets[$d] = ['installs' => [], 'events' => 0];
        }
        foreach ($dailyRows as $dr) {
            $d = $dr->occurred_at?->format('Y-m-d');
            if ($d !== null && isset($dailyBuckets[$d])) {
                $dailyBuckets[$d]['events']++;
                $dailyBuckets[$d]['installs'][$dr->installation_id] = true;
            }
        }
        $dailyActive7d = [];
        foreach ($dailyBuckets as $date => $bucket) {
            $dailyActive7d[] = [
                'date' => $date,
                'active_installations' => count($bucket['installs']),
                'total_events' => $bucket['events'],
            ];
        }

        $analyticsSummary = [
            'total_users' => User::count(),
            'active_users_7d' => User::where('updated_at', '>=', now()->subDays(7))->count(),
            'total_devices' => UserDevice::count(),
            'total_events' => AnalyticsEvent::count(),
            'active_installations_24h' => AnalyticsEvent::where('occurred_at', '>=', now()->subDay())
                ->distinct('installation_id')
                ->count('installation_id'),
            'active_installations_7d' => AnalyticsEvent::where('occurred_at', '>=', now()->subDays(7))
                ->distinct('installation_id')
                ->count('installation_id'),
            'total_duration_seconds' => $totalDurationSeconds,
            'avg_duration_seconds' => $durationSamples > 0
                ? (int) round($totalDurationSeconds / $durationSamples)
                : 0,
            'duration_samples' => $durationSamples,
            'error_events_7d' => AnalyticsEvent::where('occurred_at', '>=', now()->subDays(7))
                ->whereIn('event_name', ['playback_error', 'network_error', 'crash_report_automatic'])
                ->count(),
            'daily_active_7d' => $dailyActive7d,
            'top_searches' => array_slice($searchCounts, 0, 10, true),
            'top_playlists' => array_slice($playlistCounts, 0, 10, true),
            'top_channels' => array_slice($channelCounts, 0, 10, true),
            'grouped_player_errors' => array_slice($playerErrorCounts, 0, 10, true),
            'sync_failures' => array_slice($syncFailureCounts, 0, 10, true),
            'retention_days' => (int) config('mediacenter.analytics_retention_days', 90),
            'top_events' => AnalyticsEvent::select('event_name', DB::raw('COUNT(*) as total'))
                ->groupBy('event_name')
                ->orderByDesc('total')
                ->limit(10)
                ->get(),
            'by_platform' => AnalyticsEvent::select('platform', DB::raw('COUNT(*) as total'))
                ->groupBy('platform')
                ->get(),
            'by_version' => AnalyticsEvent::select('app_version', DB::raw('COUNT(*) as total'))
                ->whereNotNull('app_version')
                ->groupBy('app_version')
                ->orderByDesc('total')
                ->limit(10)
                ->get(),
        ];

        return view('admin.dashboard', compact(
            'user',
            'announcements',
            'releases',
            'm3uSources',
            'feedbacks',
            'auditLogs',
            'users',
            'analyticsSummary'
        ));
    }

    public function storeAnnouncement(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'title' => ['required', 'string', 'max:160'],
            'body' => ['required', 'string', 'max:2000'],
            'type' => ['required', 'in:info,maintenance,feature,warning'],
            'action_label' => ['nullable', 'string', 'max:60'],
            'action_url' => ['nullable', 'url:http,https', 'max:512'],
            'sort_order' => ['nullable', 'integer'],
        ]);

        $ann = Announcement::create([
            ...$data,
            'is_active' => true,
            'sort_order' => $data['sort_order'] ?? 0,
            'created_by' => $request->user()->id,
        ]);

        $this->audit($request->user(), 'announcement_created', 'announcement', (string) $ann->id, ['title' => $ann->title]);
        return back()->with('status', 'Pengumuman berhasil ditambahkan.');
    }

    public function toggleAnnouncement(Request $request, Announcement $announcement): RedirectResponse
    {
        $announcement->update(['is_active' => !$announcement->is_active]);
        $this->audit($request->user(), 'announcement_toggled', 'announcement', (string) $announcement->id, ['is_active' => $announcement->is_active]);
        return back()->with('status', 'Status pengumuman diperbarui.');
    }

    public function deleteAnnouncement(Request $request, Announcement $announcement): RedirectResponse
    {
        $id = $announcement->id;
        $announcement->delete();
        $this->audit($request->user(), 'announcement_deleted', 'announcement', (string) $id);
        return back()->with('status', 'Pengumuman dihapus.');
    }

    public function storeRelease(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'version' => ['required', 'string', 'max:32'],
            'build_number' => ['required', 'integer', 'min:1'],
            'platform' => ['required', 'in:android,android_tv,windows'],
            'abi' => ['required', 'string', 'max:24'],
            'download_url' => ['required', 'url:http,https', 'max:512'],
            'checksum_sha256' => ['nullable', 'string', 'max:64'],
            'size_bytes' => ['nullable', 'integer', 'min:0'],
            'min_supported_version' => ['nullable', 'string', 'max:32'],
            'enforce_min_version' => ['sometimes', 'boolean'],
            'release_notes' => ['nullable', 'string', 'max:4000'],
        ]);

        $rel = AppRelease::create([
            ...$data,
            'enforce_min_version' => (bool) ($data['enforce_min_version'] ?? false),
            'is_active' => true,
            'published_at' => now(),
        ]);

        $this->audit($request->user(), 'release_created', 'app_release', (string) $rel->id, [
            'version' => $rel->version,
            'platform' => $rel->platform,
        ]);
        return back()->with('status', 'Metadata rilis ditambahkan.');
    }

    public function storeM3uSource(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'category' => ['required', 'string', 'max:60'],
            'region' => ['nullable', 'string', 'max:80'],
            'city' => ['nullable', 'string', 'max:80'],
            'language' => ['nullable', 'string', 'max:40'],
            'status' => ['sometimes', 'in:draft,published,scheduled'],
            'scheduled_at' => ['nullable', 'date', 'required_if:status,scheduled'],
            'source_type' => ['required', 'in:url,file'],
            'source_url' => ['nullable', 'url', 'max:1024', 'required_if:source_type,url'],
            'm3u_file' => ['nullable', 'file', 'max:5120', 'required_if:source_type,file'],
        ]);

        $filePath = null;
        $sourceUrl = null;
        $sha = '';

        if ($data['source_type'] === 'url') {
            $sourceUrl = trim((string) $data['source_url']);
            $scheme = strtolower((string) parse_url($sourceUrl, PHP_URL_SCHEME));
            if (!in_array($scheme, ['http', 'https'], true)) {
                return back()->withErrors(['source_url' => 'URL M3U harus menggunakan http atau https.']);
            }
            $sha = hash('sha256', $sourceUrl . '|' . $data['name'] . '|' . $data['category']);
        } else {
            $uploaded = $request->file('m3u_file');
            $ext = strtolower($uploaded->getClientOriginalExtension());
            if (!in_array($ext, ['m3u', 'm3u8', 'txt'], true)) {
                return back()->withErrors(['m3u_file' => 'File harus berformat .m3u, .m3u8, atau .txt.']);
            }
            $filePath = Storage::disk('local')->putFile('m3u_sources', $uploaded);
            $bytes = Storage::disk('local')->get($filePath) ?? '';
            $sha = hash('sha256', $bytes);
        }

        $status = $data['status'] ?? 'published';
        $src = M3uSource::create([
            'name' => trim($data['name']),
            'category' => trim($data['category']),
            'region' => isset($data['region']) ? trim((string) $data['region']) ?: null : null,
            'city' => isset($data['city']) ? trim((string) $data['city']) ?: null : null,
            'language' => isset($data['language']) ? trim((string) $data['language']) ?: null : null,
            'source_type' => $data['source_type'],
            'source_url' => $sourceUrl,
            'file_path' => $filePath,
            'content_sha256' => $sha,
            'is_active' => true,
            'status' => $status,
            'stream_status' => 'online',
            'scheduled_at' => $status === 'scheduled' ? ($data['scheduled_at'] ?? null) : null,
            'published_at' => $status === 'published' ? now() : null,
            'created_by' => $request->user()->id,
        ]);

        M3uSourceVersion::create([
            'm3u_source_id' => $src->id,
            'version_number' => 1,
            'name' => $src->name,
            'category' => $src->category,
            'region' => $src->region,
            'city' => $src->city,
            'language' => $src->language,
            'source_type' => $src->source_type,
            'source_url' => $src->source_url,
            'file_path' => $src->file_path,
            'content_sha256' => $src->content_sha256,
            'status' => $src->status,
            'created_by' => $request->user()->id,
        ]);

        $this->audit($request->user(), 'm3u_source_created', 'm3u_source', (string) $src->id, [
            'name' => $src->name,
            'source_type' => $src->source_type,
            'status' => $src->status,
        ]);

        return back()->with('status', "Sumber M3U \"{$src->name}\" ({$src->status}) berhasil disimpan.");
    }

    public function publishM3uSource(Request $request, M3uSource $m3uSource): RedirectResponse
    {
        $m3uSource->update([
            'status' => 'published',
            'is_active' => true,
            'published_at' => now(),
        ]);
        $this->snapshotM3uVersion($m3uSource, $request->user()->id);
        $this->audit($request->user(), 'm3u_source_published', 'm3u_source', (string) $m3uSource->id);

        return back()->with('status', "Sumber M3U \"{$m3uSource->name}\" dipublikasikan.");
    }

    public function updateM3uStreamStatus(Request $request, M3uSource $m3uSource): RedirectResponse
    {
        $data = $request->validate([
            'stream_status' => ['required', 'in:online,degraded,offline'],
            'status_reason' => ['nullable', 'string', 'max:255'],
        ]);

        $m3uSource->update([
            'stream_status' => $data['stream_status'],
            'status_reason' => $data['status_reason'] ?: null,
        ]);
        $this->audit($request->user(), 'm3u_stream_status_updated', 'm3u_source', (string) $m3uSource->id, $data);

        return back()->with('status', 'Status stream M3U diperbarui.');
    }

    public function rollbackM3uSource(Request $request, M3uSource $m3uSource, M3uSourceVersion $version): RedirectResponse
    {
        if ($version->m3u_source_id !== $m3uSource->id) {
            return back()->withErrors(['m3u' => 'Versi tidak cocok dengan sumber M3U ini.']);
        }

        $m3uSource->update([
            'name' => $version->name,
            'category' => $version->category,
            'region' => $version->region,
            'city' => $version->city,
            'language' => $version->language,
            'source_type' => $version->source_type,
            'source_url' => $version->source_url,
            'file_path' => $version->file_path,
            'content_sha256' => $version->content_sha256,
            'status' => $version->status,
        ]);
        $this->snapshotM3uVersion($m3uSource, $request->user()->id);
        $this->audit($request->user(), 'm3u_source_rolled_back', 'm3u_source', (string) $m3uSource->id, [
            'version_number' => $version->version_number,
        ]);

        return back()->with('status', "Sumber M3U dikembalikan ke versi v{$version->version_number}.");
    }

    private function snapshotM3uVersion(M3uSource $src, ?int $userId): void
    {
        $nextVer = ((int) M3uSourceVersion::where('m3u_source_id', $src->id)->max('version_number')) + 1;
        M3uSourceVersion::create([
            'm3u_source_id' => $src->id,
            'version_number' => $nextVer,
            'name' => $src->name,
            'category' => $src->category,
            'region' => $src->region,
            'city' => $src->city,
            'language' => $src->language,
            'source_type' => $src->source_type,
            'source_url' => $src->source_url,
            'file_path' => $src->file_path,
            'content_sha256' => $src->content_sha256,
            'status' => $src->status,
            'created_by' => $userId,
        ]);
    }

    public function toggleM3uSource(Request $request, M3uSource $m3uSource): RedirectResponse
    {
        $m3uSource->update(['is_active' => !$m3uSource->is_active]);
        $this->audit($request->user(), 'm3u_source_toggled', 'm3u_source', (string) $m3uSource->id, [
            'is_active' => $m3uSource->is_active,
        ]);

        return back()->with('status', 'Status sumber M3U diperbarui.');
    }

    public function deleteM3uSource(Request $request, M3uSource $m3uSource): RedirectResponse
    {
        $id = $m3uSource->id;
        if ($m3uSource->file_path && Storage::disk('local')->exists($m3uSource->file_path)) {
            Storage::disk('local')->delete($m3uSource->file_path);
        }
        $m3uSource->delete();
        $this->audit($request->user(), 'm3u_source_deleted', 'm3u_source', (string) $id);

        return back()->with('status', 'Sumber M3U dihapus.');
    }

    public function updateFeedbackStatus(Request $request, FeedbackReport $feedback): RedirectResponse
    {
        $data = $request->validate([
            'status' => ['required', 'in:open,in_review,resolved,closed'],
            'admin_notes' => ['nullable', 'string', 'max:1000'],
        ]);

        $feedback->update($data);
        $this->audit($request->user(), 'feedback_updated', 'feedback_report', (string) $feedback->id, ['status' => $data['status']]);
        return back()->with('status', 'Status laporan diperbarui.');
    }

    public function pruneAnalytics(Request $request): RedirectResponse
    {
        Artisan::call('analytics:prune');
        $this->audit($request->user(), 'analytics_pruned', 'analytics_event', 'retention');

        return back()->with('status', 'Event analitik lama berhasil dibersihkan sesuai retensi.');
    }

    public function toggleUserActive(Request $request, User $targetUser): RedirectResponse
    {
        if ($targetUser->id === $request->user()->id) {
            return back()->withErrors(['user' => 'Tidak dapat menonaktifkan akun sendiri.']);
        }
        $targetUser->update(['is_active' => !$targetUser->is_active]);
        if (!$targetUser->is_active) {
            $targetUser->tokens()->delete();
        }
        $this->audit($request->user(), 'user_status_toggled', 'user', (string) $targetUser->id, ['is_active' => $targetUser->is_active]);
        return back()->with('status', 'Status pengguna diperbarui.');
    }

    private function audit(User $admin, string $action, string $targetType, string $targetId, array $details = []): void
    {
        AdminAuditLog::create([
            'admin_user_id' => $admin->id,
            'action' => $action,
            'target_type' => $targetType,
            'target_id' => $targetId,
            'details' => $details,
        ]);
    }
}
