<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('transaction_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('transaction_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->restrictOnDelete();
            // Snapshot historis: jangan direkonstruksi dari tabel products (AGENTS.md §9).
            $table->string('product_name');
            $table->unsignedInteger('quantity');
            $table->unsignedInteger('price');
            $table->unsignedBigInteger('subtotal');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transaction_items');
    }
};
