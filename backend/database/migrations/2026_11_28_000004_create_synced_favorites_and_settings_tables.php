<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('synced_favorites', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('client_uid', 80);
            $table->string('title', 200);
            $table->string('artist', 160)->nullable();
            $table->string('album', 160)->nullable();
            $table->unsignedInteger('duration_seconds')->nullable();
            $table->string('metadata_hash', 64)->nullable()->index();
            $table->string('source_type', 24)->default('local_metadata');
            $table->string('stream_url', 1024)->nullable();
            $table->boolean('is_video')->default(false);
            $table->timestamp('client_updated_at')->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'client_uid']);
        });

        Schema::create('synced_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('theme_mode', 16)->default('system');
            $table->boolean('shuffle_enabled')->default(false);
            $table->string('repeat_mode', 16)->default('off');
            $table->string('eq_preset', 40)->nullable();
            $table->decimal('playback_speed', 4, 2)->default(1.00);
            $table->json('extra_json')->nullable();
            $table->unsignedBigInteger('revision')->default(1);
            $table->timestamp('client_updated_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('synced_settings');
        Schema::dropIfExists('synced_favorites');
    }
};
