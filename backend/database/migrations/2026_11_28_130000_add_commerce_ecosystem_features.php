<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('stores', function (Blueprint $table) {
            $table->string('qris_image_url', 1024)->nullable()->after('tables_count');
            $table->string('google_maps_review_url', 1024)->nullable()->after('qris_image_url');
            $table->string('opening_hours', 120)->nullable()->after('google_maps_review_url');
            $table->boolean('is_open')->default(true)->after('opening_hours');
            $table->string('staff_pin_hash')->nullable()->after('is_open');
            $table->string('now_playing_title', 200)->nullable()->after('staff_pin_hash');
            $table->string('now_playing_artist', 160)->nullable()->after('now_playing_title');
            $table->decimal('rating_avg', 3, 2)->default(0)->after('now_playing_artist');
            $table->unsignedInteger('rating_count')->default(0)->after('rating_avg');
        });

        Schema::table('store_orders', function (Blueprint $table) {
            $table->decimal('discount_amount', 12, 2)->default(0)->after('total_amount');
            $table->string('voucher_code', 40)->nullable()->after('discount_amount');
        });

        Schema::create('store_vouchers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->string('code', 40);
            $table->string('discount_type', 16)->default('percent'); // percent | fixed
            $table->decimal('discount_value', 12, 2);
            $table->decimal('min_order', 12, 2)->default(0);
            $table->unsignedInteger('max_uses')->nullable();
            $table->unsignedInteger('used_count')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();

            $table->unique(['store_id', 'code']);
        });

        Schema::create('store_reviews', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reviewer_name', 120);
            $table->string('reviewer_whatsapp', 32)->nullable();
            $table->unsignedTinyInteger('rating');
            $table->string('comment', 500)->nullable();
            $table->boolean('is_verified_order')->default(false);
            $table->timestamps();

            $table->index(['store_id', 'created_at']);
        });

        Schema::create('store_jukebox_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->string('requester_name', 120);
            $table->string('table_number', 32)->nullable();
            $table->string('song_title', 200);
            $table->string('artist_name', 160)->nullable();
            $table->string('notes', 250)->nullable();
            $table->string('status', 16)->default('pending'); // pending | approved | played | rejected
            $table->timestamps();

            $table->index(['store_id', 'status', 'created_at']);
        });

        Schema::create('store_finance_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->string('client_uid', 80);
            $table->string('entry_type', 16); // income | expense
            $table->string('category', 80);
            $table->decimal('amount', 14, 2);
            $table->string('payment_account', 60)->nullable();
            $table->string('description', 300)->nullable();
            $table->timestamp('occurred_at')->useCurrent();
            $table->timestamps();

            $table->unique(['store_id', 'client_uid']);
            $table->index(['store_id', 'occurred_at']);
        });

        Schema::table('ad_campaigns', function (Blueprint $table) {
            $table->foreignId('store_id')->nullable()->after('created_by')->constrained('stores')->cascadeOnDelete();
            $table->string('approval_status', 16)->default('approved')->after('is_active'); // approved | pending | rejected
        });
    }

    public function down(): void
    {
        Schema::table('ad_campaigns', function (Blueprint $table) {
            $table->dropConstrainedForeignId('store_id');
            $table->dropColumn('approval_status');
        });
        Schema::dropIfExists('store_finance_entries');
        Schema::dropIfExists('store_jukebox_requests');
        Schema::dropIfExists('store_reviews');
        Schema::dropIfExists('store_vouchers');
        Schema::table('store_orders', function (Blueprint $table) {
            $table->dropColumn(['discount_amount', 'voucher_code']);
        });
        Schema::table('stores', function (Blueprint $table) {
            $table->dropColumn([
                'qris_image_url',
                'google_maps_review_url',
                'opening_hours',
                'is_open',
                'staff_pin_hash',
                'now_playing_title',
                'now_playing_artist',
                'rating_avg',
                'rating_count',
            ]);
        });
    }
};
