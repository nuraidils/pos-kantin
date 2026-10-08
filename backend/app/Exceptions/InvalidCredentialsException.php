<?php

namespace App\Exceptions;

use Exception;
use Illuminate\Http\JsonResponse;

class InvalidCredentialsException extends Exception
{
    public function render(): JsonResponse
    {
        return response()->json(['message' => 'Email atau kata sandi salah.'], 401);
    }
}
