<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AdminAuditLog;
use App\Models\AnalyticsEvent;
use App\Models\Announcement;
use App\Models\AppRelease;
use App\Models\FeedbackReport;
use App\Models\M3uSource;
use App\Models\User;
use App\Models\UserDevice;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
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
        $m3uSources = M3uSource::orderByDesc('updated_at')->get();
        $feedbacks = FeedbackReport::orderByDesc('created_at')->limit(50)->get();
        $auditLogs = AdminAuditLog::with('adminUser')->orderByDesc('created_at')->limit(30)->get();
        $users = $user->role === User::ROLE_SUPER_ADMIN
            ? User::orderByDesc('created_at')->limit(50)->get()
            : collect();

        $recentPropsEvents = AnalyticsEvent::whereNotNull('properties')
            ->orderByDesc('occurred_at')
            ->limit(500)
            ->get(['properties']);

        $totalDurationSeconds = 0;
        $durationSamples = 0;
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

        $src = M3uSource::create([
            'name' => trim($data['name']),
            'category' => trim($data['category']),
            'source_type' => $data['source_type'],
            'source_url' => $sourceUrl,
            'file_path' => $filePath,
            'content_sha256' => $sha,
            'is_active' => true,
            'created_by' => $request->user()->id,
        ]);

        $this->audit($request->user(), 'm3u_source_created', 'm3u_source', (string) $src->id, [
            'name' => $src->name,
            'source_type' => $src->source_type,
        ]);

        return back()->with('status', "Sumber M3U \"{$src->name}\" berhasil disimpan.");
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
