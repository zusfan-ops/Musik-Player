<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('announcements', function (Blueprint $table) {
            $table->id();
            $table->string('title', 160);
            $table->text('body');
            $table->string('type', 24)->default('info');
            $table->string('action_label', 60)->nullable();
            $table->string('action_url', 512)->nullable();
            $table->boolean('is_active')->default(true)->index();
            $table->integer('sort_order')->default(0);
            $table->timestamp('starts_at')->nullable()->index();
            $table->timestamp('ends_at')->nullable()->index();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('app_releases', function (Blueprint $table) {
            $table->id();
            $table->string('version', 32);
            $table->unsignedInteger('build_number')->default(1);
            $table->string('platform', 24)->index();
            $table->string('abi', 24)->default('arm64-v8a');
            $table->string('download_url', 512);
            $table->string('checksum_sha256', 64)->nullable();
            $table->unsignedBigInteger('size_bytes')->nullable();
            $table->string('min_supported_version', 32)->nullable();
            $table->boolean('enforce_min_version')->default(false);
            $table->text('release_notes')->nullable();
            $table->boolean('is_active')->default(true)->index();
            $table->timestamp('published_at')->nullable();
            $table->timestamps();

            $table->index(['platform', 'abi', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_releases');
        Schema::dropIfExists('announcements');
    }
};
