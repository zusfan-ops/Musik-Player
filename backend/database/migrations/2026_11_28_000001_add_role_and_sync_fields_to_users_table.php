<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('role', 32)->default('user')->after('password')->index();
            $table->boolean('is_active')->default(true)->after('role');
            $table->unsignedBigInteger('sync_revision')->default(0)->after('is_active');
            $table->boolean('analytics_opted_in')->default(false)->after('sync_revision');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['role', 'is_active', 'sync_revision', 'analytics_opted_in']);
        });
    }
};
