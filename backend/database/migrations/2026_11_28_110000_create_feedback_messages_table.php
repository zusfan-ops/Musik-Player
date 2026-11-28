<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feedback_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('feedback_report_id')
                ->constrained('feedback_reports')
                ->cascadeOnDelete();
            $table->string('sender_type', 16); // user | admin
            $table->foreignId('sender_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('sender_name', 120)->nullable();
            $table->text('body');
            $table->timestamps();

            $table->index(['feedback_report_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feedback_messages');
    }
};
