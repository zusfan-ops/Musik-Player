<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('m3u_sources', function (Blueprint $table) {
            $table->id();
            $table->string('name', 120);
            $table->string('category', 60)->default('TV & CCTV');
            $table->string('source_type', 16); // url | file
            $table->string('source_url', 1024)->nullable();
            $table->string('file_path', 512)->nullable();
            $table->string('content_sha256', 64);
            $table->boolean('is_active')->default(true);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('m3u_sources');
    }
};
