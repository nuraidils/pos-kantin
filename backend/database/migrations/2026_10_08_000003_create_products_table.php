<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('category_id')->constrained()->restrictOnDelete();
            $table->string('image')->nullable();
            $table->string('name');
            $table->unsignedInteger('price');
            // unsigned: database ikut menolak stok negatif (AGENTS.md §13.4).
            $table->unsignedInteger('stock')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();

            $table->index('updated_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('products');
    }
};
