<?php

namespace App\Models;

use App\Enums\UserRole;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements FilamentUser
{
    use HasApiTokens, HasFactory, Notifiable;

    // 'role' sengaja TIDAK mass-assignable: role hanya ditetapkan manual
    // (tinker/seeder), tidak pernah dari input request (AGENTS.md §8).
    protected $fillable = ['name', 'email', 'password'];

    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => UserRole::class,
        ];
    }

    public function isOwner(): bool
    {
        return $this->role === UserRole::Owner;
    }

    public function isCashier(): bool
    {
        return $this->role === UserRole::Cashier;
    }

    /** Hanya owner yang boleh masuk dashboard Filament. */
    public function canAccessPanel(Panel $panel): bool
    {
        return $this->isOwner();
    }
}
