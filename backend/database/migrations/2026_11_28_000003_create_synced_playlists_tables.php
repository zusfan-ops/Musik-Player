<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('synced_playlists', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('client_uid', 80);
            $table->string('name', 160);
            $table->string('source_type', 24)->default('metadata_only');
            $table->string('source_url', 1024)->nullable();
            $table->unsignedBigInteger('revision')->default(1);
            $table->boolean('is_enabled')->default(true);
            $table->timestamp('client_updated_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['user_id', 'client_uid']);
        });

        Schema::create('synced_playlist_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('synced_playlist_id')->constrained()->cascadeOnDelete();
            $table->string('client_uid', 80);
            $table->unsignedInteger('position')->default(0);
            $table->string('title', 200);
            $table->string('artist', 160)->nullable();
            $table->string('album', 160)->nullable();
            $table->string('group_title', 160)->nullable();
            $table->unsignedInteger('duration_seconds')->nullable();
            $table->string('metadata_hash', 64)->nullable()->index();
            $table->string('stream_url', 1024)->nullable();
            $table->boolean('is_video')->default(false);
            $table->unsignedInteger('last_position_seconds')->default(0);
            $table->timestamps();

            $table->index(['synced_playlist_id', 'position']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('synced_playlist_items');
        Schema::dropIfExists('synced_playlists');
    }
};
