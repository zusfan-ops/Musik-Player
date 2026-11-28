<?php

namespace App\Console\Commands;

use App\Models\AnalyticsEvent;
use Illuminate\Console\Command;

class PruneAnalyticsEvents extends Command
{
    protected $signature = 'analytics:prune {--days= : Override retention days}';

    protected $description = 'Deletes analytics events older than the configured retention period.';

    public function handle(): int
    {
        $days = (int) ($this->option('days') ?: config('mediacenter.analytics_retention_days', 90));
        $cutoff = now()->subDays(max(1, $days));
        $deleted = AnalyticsEvent::where('occurred_at', '<', $cutoff)->delete();
        $this->info("Pruned {$deleted} analytics events older than {$days} days.");
        return self::SUCCESS;
    }
}
