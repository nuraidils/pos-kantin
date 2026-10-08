<?php

namespace App\Exceptions;

use Exception;
use Illuminate\Http\JsonResponse;

class RoleNotAllowedException extends Exception
{
    public function render(): JsonResponse
    {
        return response()->json([
            'message' => 'Akun ini tidak dapat masuk lewat aplikasi kasir. Gunakan dashboard web.',
        ], 403);
    }
}
