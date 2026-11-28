<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\AnalyticsEvent;
use App\Support\SyncSanitizer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AnalyticsController extends Controller
{
    public function storeEvents(Request $request): JsonResponse
    {
        $maxBatch = config('mediacenter.analytics_max_batch_size', 50);
        $allowedEvents = config('mediacenter.allowed_analytics_events', []);
        $forbiddenAttrs = config('mediacenter.forbidden_analytics_attributes', []);

        $data = $request->validate([
            'installation_id' => ['required', 'string', 'min:8', 'max:64', 'regex:/^[a-zA-Z0-9\-_]+$/'],
            'events' => ['required', 'array', 'min:1', "max:$maxBatch"],
            'events.*.event' => ['required', 'string', Rule::in($allowedEvents)],
            'events.*.platform' => ['required', 'string', 'in:android,android_tv,windows,linux,macos,ios'],
            'events.*.app_version' => ['nullable', 'string', 'max:32'],
            'events.*.occurred_at' => ['nullable', 'date'],
            'events.*.properties' => ['nullable', 'array'],
        ]);

        $now = now();
        $rows = [];
        foreach ($data['events'] as $ev) {
            $cleanProps = SyncSanitizer::sanitizeExtraMap($ev['properties'] ?? [], $forbiddenAttrs);
            $rows[] = [
                'installation_id' => $data['installation_id'],
                'event_name' => $ev['event'],
                'platform' => $ev['platform'],
                'app_version' => $ev['app_version'] ?? null,
                'properties' => empty($cleanProps) ? null : json_encode($cleanProps),
                'occurred_at' => isset($ev['occurred_at']) ? date('Y-m-d H:i:s', strtotime($ev['occurred_at'])) : $now,
                'created_at' => $now,
            ];
        }

        AnalyticsEvent::insert($rows);

        return response()->json([
            'accepted' => count($rows),
        ], 202);
    }

    public function deleteInstallationEvents(Request $request, string $installationId): JsonResponse
    {
        if (!preg_match('/^[a-zA-Z0-9\-_]{8,64}$/', $installationId)) {
            return response()->json(['message' => 'Installation ID tidak valid.'], 422);
        }

        $deleted = AnalyticsEvent::where('installation_id', $installationId)->delete();

        return response()->json([
            'message' => 'Riwayat analitik perangkat berhasil dihapus.',
            'deleted_count' => $deleted,
        ]);
    }
}
