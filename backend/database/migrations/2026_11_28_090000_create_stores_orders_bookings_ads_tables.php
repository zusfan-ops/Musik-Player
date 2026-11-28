<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('phone', 30)->nullable()->after('email');
            $table->timestamp('suspended_until')->nullable()->after('is_active');
            $table->string('suspension_reason', 255)->nullable()->after('suspended_until');
        });

        Schema::create('stores', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained('users')->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('slug', 64)->unique();
            $table->string('store_type', 40)->default('umum'); // coffeeshop | resto | retail | jasa | umum
            $table->string('description', 500)->nullable();
            $table->string('address', 300)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('whatsapp_number', 30)->nullable();
            $table->unsignedSmallInteger('tables_count')->default(0);
            $table->boolean('is_active')->default(true);
            $table->unsignedBigInteger('views_count')->default(0);
            $table->timestamps();
        });

        Schema::create('store_products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->string('client_uid', 80);
            $table->string('name', 140);
            $table->string('category', 60)->default('Umum');
            $table->decimal('price', 12, 2)->default(0);
            $table->integer('stock')->default(0);
            $table->string('unit', 20)->default('pcs');
            $table->string('description', 300)->nullable();
            $table->string('image_url', 512)->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedBigInteger('views_count')->default(0);
            $table->timestamps();

            $table->unique(['store_id', 'client_uid']);
        });

        Schema::create('store_customers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('whatsapp', 30);
            $table->unsignedInteger('orders_count')->default(1);
            $table->timestamp('last_order_at')->nullable();
            $table->timestamps();

            $table->unique(['store_id', 'whatsapp']);
        });

        Schema::create('store_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('store_customer_id')->nullable()->constrained('store_customers')->nullOnDelete();
            $table->string('order_code', 32)->unique();
            $table->string('customer_name', 120);
            $table->string('customer_whatsapp', 30);
            $table->string('table_number', 20)->nullable();
            $table->string('notes', 300)->nullable();
            $table->json('items_json');
            $table->decimal('total_amount', 12, 2)->default(0);
            $table->string('status', 24)->default('queued'); // queued | preparing | completed | cancelled
            $table->timestamps();
        });

        Schema::create('store_bookings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('customer_name', 120);
            $table->string('customer_whatsapp', 30);
            $table->string('table_number', 20);
            $table->unsignedSmallInteger('guests_count')->default(2);
            $table->timestamp('booking_time');
            $table->string('notes', 300)->nullable();
            $table->string('status', 24)->default('pending'); // pending | confirmed | cancelled
            $table->timestamps();
        });

        Schema::create('ad_campaigns', function (Blueprint $table) {
            $table->id();
            $table->string('title', 140);
            $table->string('description', 300)->nullable();
            $table->string('media_type', 16)->default('image'); // image | video
            $table->string('media_url', 1024);
            $table->string('target_url', 1024)->nullable();
            $table->string('placement', 32)->default('home_feed'); // home_feed | store_feed
            $table->boolean('is_active')->default(true);
            $table->unsignedBigInteger('impressions_count')->default(0);
            $table->unsignedBigInteger('clicks_count')->default(0);
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ad_campaigns');
        Schema::dropIfExists('store_bookings');
        Schema::dropIfExists('store_orders');
        Schema::dropIfExists('store_customers');
        Schema::dropIfExists('store_products');
        Schema::dropIfExists('stores');
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['phone', 'suspended_until', 'suspension_reason']);
        });
    }
};
