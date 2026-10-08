<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    private function makeUser(string $role): User
    {
        return User::factory()->create([
            'email' => "$role@example.test",
            'password' => 'rahasia-123',
            'role' => $role,
        ]);
    }

    public function test_kasir_bisa_masuk_dan_menerima_token(): void
    {
        $this->makeUser('cashier');

        $this->postJson('/api/auth/login', [
            'email' => 'cashier@example.test',
            'password' => 'rahasia-123',
            'device_name' => 'hp-kasir',
        ])
            ->assertOk()
            ->assertJsonStructure(['data' => ['token', 'user' => ['id', 'name', 'email', 'role']]])
            ->assertJsonPath('data.user.role', 'cashier');
    }

    public function test_kata_sandi_salah_ditolak_dengan_401(): void
    {
        $this->makeUser('cashier');

        $this->postJson('/api/auth/login', [
            'email' => 'cashier@example.test',
            'password' => 'salah',
        ])->assertUnauthorized();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_owner_tidak_bisa_masuk_lewat_api_mobile(): void
    {
        $this->makeUser('owner');

        $this->postJson('/api/auth/login', [
            'email' => 'owner@example.test',
            'password' => 'rahasia-123',
        ])->assertForbidden();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_input_tidak_valid_menghasilkan_422(): void
    {
        $this->postJson('/api/auth/login', ['email' => 'bukan-email'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['email', 'password']);
    }

    public function test_keluar_menghapus_token(): void
    {
        $this->makeUser('cashier');

        $token = $this->postJson('/api/auth/login', [
            'email' => 'cashier@example.test',
            'password' => 'rahasia-123',
        ])->json('data.token');

        $this->withToken($token)->postJson('/api/auth/logout')->assertNoContent();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_role_tidak_bisa_diisi_lewat_mass_assignment(): void
    {
        $user = User::create([
            'name' => 'Uji', 'email' => 'uji@example.test',
            'password' => 'rahasia-123', 'role' => 'owner',
        ]);

        $this->assertTrue($user->fresh()->isCashier());
    }
}
