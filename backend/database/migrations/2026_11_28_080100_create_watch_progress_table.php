<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('watch_progress', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('content_key', 120);
            $table->string('title', 200);
            $table->string('content_type', 24)->default('video'); // video | series | stream
            $table->unsignedInteger('position_seconds')->default(0);
            $table->unsignedInteger('duration_seconds')->default(0);
            $table->string('stream_url', 1024)->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'content_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('watch_progress');
    }
};
