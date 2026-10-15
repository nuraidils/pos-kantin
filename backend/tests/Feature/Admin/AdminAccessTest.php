<?php

namespace Tests\Feature\Admin;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Hanya owner yang boleh masuk dashboard (AGENTS.md §8). */
class AdminAccessTest extends TestCase
{
    use RefreshDatabase;

    public function test_tamu_diarahkan_ke_halaman_masuk(): void
    {
        $this->get('/admin')->assertRedirect('/admin/login');
        $this->get('/admin/products')->assertRedirect('/admin/login');
    }

    public function test_kasir_tidak_boleh_membuka_dashboard(): void
    {
        $kasir = User::factory()->create(['role' => 'cashier']);

        $this->actingAs($kasir)->get('/admin')->assertForbidden();
        $this->actingAs($kasir)->get('/admin/products')->assertForbidden();
        $this->actingAs($kasir)->get('/admin/transactions')->assertForbidden();
        $this->actingAs($kasir)->get('/admin/laporan')->assertForbidden();
    }

    public function test_owner_dapat_membuka_semua_halaman(): void
    {
        $owner = User::factory()->create(['role' => 'owner']);

        foreach (['/admin', '/admin/products', '/admin/products/create', '/admin/categories', '/admin/transactions', '/admin/laporan'] as $path) {
            $this->actingAs($owner)->get($path)->assertOk();
        }
    }

    public function test_transaksi_tidak_bisa_dibuat_dari_dashboard(): void
    {
        $owner = User::factory()->create(['role' => 'owner']);

        // Halaman buat memang tidak didaftarkan: transaksi hanya lahir di perangkat kasir.
        $this->actingAs($owner)->get('/admin/transactions/create')->assertNotFound();
    }
}
