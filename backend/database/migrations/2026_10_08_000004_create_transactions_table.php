<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('transactions', function (Blueprint $table) {
            $table->id();
            // Kunci idempotensi dari Flutter (AGENTS.md §10).
            $table->uuid('local_uuid')->unique();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('invoice_number', 40)->unique();
            $table->unsignedBigInteger('total_amount');
            $table->string('payment_method', 10); // cash | qris
            $table->string('sync_status', 10)->default('synced');
            // created_at = waktu penjualan menurut perangkat, bukan waktu upload.
            $table->timestamp('created_at')->useCurrent()->index();
            $table->timestamp('synced_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transactions');
    }
};
