<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ad_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('ad_campaign_id')
                ->constrained('ad_campaigns')
                ->cascadeOnDelete();
            $table->string('event_type', 16); // impression | click
            $table->string('placement', 32)->default('home_feed');
            $table->string('platform', 32)->default('unknown');
            $table->string('installation_id', 64)->nullable();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('occurred_at')->useCurrent();

            $table->index(['ad_campaign_id', 'event_type', 'occurred_at']);
            $table->index(['event_type', 'occurred_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ad_events');
    }
};
