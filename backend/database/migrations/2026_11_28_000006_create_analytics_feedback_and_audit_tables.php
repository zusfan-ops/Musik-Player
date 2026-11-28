<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('analytics_events', function (Blueprint $table) {
            $table->id();
            $table->string('installation_id', 64)->index();
            $table->string('event_name', 64)->index();
            $table->string('platform', 24)->index();
            $table->string('app_version', 32)->nullable();
            $table->json('properties')->nullable();
            $table->timestamp('occurred_at')->index();
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('feedback_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('installation_id', 64)->nullable()->index();
            $table->string('category', 32)->default('bug');
            $table->text('message');
            $table->string('platform', 24)->default('android');
            $table->string('app_version', 32)->nullable();
            $table->boolean('diagnostics_consent')->default(false);
            $table->json('diagnostics_json')->nullable();
            $table->string('status', 24)->default('open')->index();
            $table->text('admin_notes')->nullable();
            $table->timestamps();
        });

        Schema::create('admin_audit_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('admin_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('action', 64)->index();
            $table->string('target_type', 64)->nullable();
            $table->string('target_id', 64)->nullable();
            $table->json('details')->nullable();
            $table->timestamp('created_at')->useCurrent()->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('admin_audit_logs');
        Schema::dropIfExists('feedback_reports');
        Schema::dropIfExists('analytics_events');
    }
};
