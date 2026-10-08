<?php

namespace App\Services;

use App\Exceptions\InvalidCredentialsException;
use App\Exceptions\RoleNotAllowedException;
use App\Models\User;
use Illuminate\Support\Facades\Hash;

class AuthService
{
    /**
     * Login untuk aplikasi kasir (Flutter). Hanya role 'cashier' yang boleh.
     * Role owner masuk lewat Filament, bukan token mobile.
     *
     * @return array{user: User, token: string}
     *
     * @throws InvalidCredentialsException
     * @throws RoleNotAllowedException
     */
    public function loginCashier(string $email, string $password, string $deviceName): array
    {
        $user = User::query()->where('email', $email)->first();

        if (! $user || ! Hash::check($password, $user->password)) {
            throw new InvalidCredentialsException;
        }

        if (! $user->isCashier()) {
            throw new RoleNotAllowedException;
        }

        // Satu token aktif per perangkat: login ulang menggantikan token lama.
        $user->tokens()->where('name', $deviceName)->delete();

        return [
            'user' => $user,
            'token' => $user->createToken($deviceName)->plainTextToken,
        ];
    }
}
