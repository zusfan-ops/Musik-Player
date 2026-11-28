<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AdminAuditLog;
use App\Models\AnalyticsEvent;
use App\Models\Announcement;
use App\Models\AppRelease;
use App\Models\FeedbackReport;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;

class AdminController extends Controller
{
    public function showLogin(): View|RedirectResponse
    {
        if (Auth::check() && Auth::user()?->isAdmin()) {
            return redirect()->route('admin.dashboard');
        }
        return view('admin.login');
    }

    public function login(Request $request): RedirectResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

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
        $feedbacks = FeedbackReport::orderByDesc('created_at')->limit(50)->get();
        $auditLogs = AdminAuditLog::with('adminUser')->orderByDesc('created_at')->limit(30)->get();
        $users = $user->role === User::ROLE_SUPER_ADMIN
            ? User::orderByDesc('created_at')->limit(50)->get()
            : collect();

        $analyticsSummary = [
            'total_events' => AnalyticsEvent::count(),
            'active_installations_7d' => AnalyticsEvent::where('occurred_at', '>=', now()->subDays(7))
                ->distinct('installation_id')
                ->count('installation_id'),
            'top_events' => AnalyticsEvent::select('event_name', DB::raw('COUNT(*) as total'))
                ->groupBy('event_name')
                ->orderByDesc('total')
                ->limit(10)
                ->get(),
            'by_platform' => AnalyticsEvent::select('platform', DB::raw('COUNT(*) as total'))
                ->groupBy('platform')
                ->get(),
        ];

        return view('admin.dashboard', compact(
            'user',
            'announcements',
            'releases',
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
            'action_url' => ['nullable', 'url', 'max:512'],
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
            'download_url' => ['required', 'url', 'max:512'],
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
