<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\FeedbackReport;
use App\Support\SyncSanitizer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FeedbackController extends Controller
{
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

        $report = FeedbackReport::create([
            'user_id' => $request->user('sanctum')?->id,
            'installation_id' => $data['installation_id'] ?? null,
            'category' => $data['category'],
            'message' => $data['message'],
            'platform' => $data['platform'],
            'app_version' => $data['app_version'] ?? null,
            'diagnostics_consent' => $consent,
            'diagnostics_json' => $cleanDiagnostics,
            'status' => 'open',
        ]);

        return response()->json([
            'message' => 'Terima kasih, laporan Anda telah diterima.',
            'data' => [
                'id' => $report->id,
                'category' => $report->category,
                'status' => $report->status,
                'created_at' => $report->created_at?->toIso8601String(),
            ],
        ], 201);
    }
}
