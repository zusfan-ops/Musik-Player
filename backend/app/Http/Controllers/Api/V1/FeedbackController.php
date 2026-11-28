<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\FeedbackMessage;
use App\Models\FeedbackReport;
use App\Support\SyncSanitizer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FeedbackController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'installation_id' => ['nullable', 'string', 'max:64', 'regex:/^[a-zA-Z0-9\-_]+$/'],
        ]);

        $user = $request->user('sanctum');
        $installId = $validated['installation_id'] ?? null;

        if (!$user && !$installId) {
            return response()->json(['data' => []]);
        }

        $query = FeedbackReport::with('messages')->orderByDesc('updated_at');

        if ($user) {
            $query->where(function ($q) use ($user, $installId) {
                $q->where('user_id', $user->id);
                if ($installId) {
                    $q->orWhere(function ($q2) use ($installId) {
                        $q2->whereNull('user_id')->where('installation_id', $installId);
                    });
                }
            });
        } else {
            $query->whereNull('user_id')->where('installation_id', $installId);
        }

        $reports = $query->limit(30)->get();

        return response()->json([
            'data' => $reports->map(fn (FeedbackReport $r) => $this->serializeReport($r))->values(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'installation_id' => ['nullable', 'string', 'max:64', 'regex:/^[a-zA-Z0-9\-_]+$/'],
            'category' => ['required', 'string', 'in:bug,feature,complaint,playback,other'],
            'message' => ['required', 'string', 'min:5', 'max:2000'],
            'platform' => ['required', 'string', 'in:android,android_tv,windows,linux,macos,ios'],
            'app_version' => ['nullable', 'string', 'max:32'],
            'diagnostics_consent' => ['sometimes', 'boolean'],
            'diagnostics' => ['nullable', 'array'],
        ]);

        $consent = (bool) ($data['diagnostics_consent'] ?? false);
        $cleanDiagnostics = $consent
            ? SyncSanitizer::sanitizeExtraMap(
                $data['diagnostics'] ?? [],
                config('mediacenter.forbidden_analytics_attributes', [])
            )
            : null;

        $user = $request->user('sanctum');

        $report = FeedbackReport::create([
            'user_id' => $user?->id,
            'installation_id' => $data['installation_id'] ?? null,
            'category' => $data['category'],
            'message' => $data['message'],
            'platform' => $data['platform'],
            'app_version' => $data['app_version'] ?? null,
            'diagnostics_consent' => $consent,
            'diagnostics_json' => $cleanDiagnostics,
            'status' => 'open',
        ]);

        FeedbackMessage::create([
            'feedback_report_id' => $report->id,
            'sender_type' => 'user',
            'sender_id' => $user?->id,
            'sender_name' => $user?->name ?? 'Pengguna',
            'body' => $data['message'],
        ]);

        $report->load('messages');

        return response()->json([
            'message' => 'Terima kasih, laporan Anda telah diterima.',
            'data' => $this->serializeReport($report),
        ], 201);
    }

    public function show(Request $request, FeedbackReport $feedback): JsonResponse
    {
        $validated = $request->validate([
            'installation_id' => ['nullable', 'string', 'max:64', 'regex:/^[a-zA-Z0-9\-_]+$/'],
        ]);

        $this->authorizeAccess($request, $feedback, $validated['installation_id'] ?? null);
        $feedback->load('messages');

        return response()->json([
            'data' => $this->serializeReport($feedback),
        ]);
    }

    public function reply(Request $request, FeedbackReport $feedback): JsonResponse
    {
        $data = $request->validate([
            'installation_id' => ['nullable', 'string', 'max:64', 'regex:/^[a-zA-Z0-9\-_]+$/'],
            'message' => ['required', 'string', 'min:2', 'max:2000'],
        ]);

        $this->authorizeAccess($request, $feedback, $data['installation_id'] ?? null);
        $user = $request->user('sanctum');

        FeedbackMessage::create([
            'feedback_report_id' => $feedback->id,
            'sender_type' => 'user',
            'sender_id' => $user?->id,
            'sender_name' => $user?->name ?? 'Pengguna',
            'body' => trim($data['message']),
        ]);

        if (in_array($feedback->status, ['resolved', 'closed'], true)) {
            $feedback->status = 'in_review';
        }
        $feedback->touch();
        $feedback->save();
        $feedback->load('messages');

        return response()->json([
            'message' => 'Balasan terkirim ke admin.',
            'data' => $this->serializeReport($feedback),
        ], 201);
    }

    private function authorizeAccess(Request $request, FeedbackReport $feedback, ?string $installId): void
    {
        $user = $request->user('sanctum');

        if ($user && $feedback->user_id === $user->id) {
            return;
        }

        if ($feedback->user_id === null && $installId !== null && $feedback->installation_id === $installId) {
            return;
        }

        abort(403, 'Anda tidak memiliki akses ke tiket ini.');
    }

    private function serializeReport(FeedbackReport $report): array
    {
        $messages = $report->messages->map(fn (FeedbackMessage $m) => [
            'id' => $m->id,
            'sender_type' => $m->sender_type,
            'sender_name' => $m->sender_name ?? ($m->sender_type === 'admin' ? 'Admin' : 'Pengguna'),
            'body' => $m->body,
            'created_at' => $m->created_at?->toIso8601String(),
        ])->values()->all();

        if (empty($messages)) {
            $messages[] = [
                'id' => 0,
                'sender_type' => 'user',
                'sender_name' => 'Pengguna',
                'body' => $report->message,
                'created_at' => $report->created_at?->toIso8601String(),
            ];
            if (!empty($report->admin_notes)) {
                $messages[] = [
                    'id' => 0,
                    'sender_type' => 'admin',
                    'sender_name' => 'Admin',
                    'body' => $report->admin_notes,
                    'created_at' => $report->updated_at?->toIso8601String(),
                ];
            }
        }

        return [
            'id' => $report->id,
            'category' => $report->category,
            'message' => $report->message,
            'platform' => $report->platform,
            'app_version' => $report->app_version,
            'status' => $report->status,
            'admin_notes' => $report->admin_notes,
            'created_at' => $report->created_at?->toIso8601String(),
            'updated_at' => $report->updated_at?->toIso8601String(),
            'messages' => $messages,
        ];
    }
}
