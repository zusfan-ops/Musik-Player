<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('m3u_sources', function (Blueprint $table) {
            $table->string('status', 20)->default('published')->after('is_active'); // draft | published | scheduled
            $table->string('region', 80)->nullable()->after('category');
            $table->string('city', 80)->nullable()->after('region');
            $table->string('language', 40)->nullable()->after('city');
            $table->string('stream_status', 24)->default('online')->after('status'); // online | degraded | offline
            $table->string('status_reason', 255)->nullable()->after('stream_status');
            $table->timestamp('scheduled_at')->nullable()->after('status_reason');
            $table->timestamp('published_at')->nullable()->after('scheduled_at');
        });

        Schema::create('m3u_source_versions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('m3u_source_id')->constrained('m3u_sources')->cascadeOnDelete();
            $table->unsignedInteger('version_number');
            $table->string('name', 120);
            $table->string('category', 60);
            $table->string('region', 80)->nullable();
            $table->string('city', 80)->nullable();
            $table->string('language', 40)->nullable();
            $table->string('source_type', 16);
            $table->string('source_url', 1024)->nullable();
            $table->string('file_path', 512)->nullable();
            $table->string('content_sha256', 64);
            $table->string('status', 20);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('m3u_source_versions');
        Schema::table('m3u_sources', function (Blueprint $table) {
            $table->dropColumn([
                'status',
                'region',
                'city',
                'language',
                'stream_status',
                'status_reason',
                'scheduled_at',
                'published_at',
            ]);
        });
    }
};
