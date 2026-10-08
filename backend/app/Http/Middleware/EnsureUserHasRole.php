<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Pemakaian: ->middleware('role:cashier') atau 'role:owner,cashier'.
 * Role selalu dibaca dari database lewat user terautentikasi, bukan dari request.
 */
class EnsureUserHasRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $role = $request->user()?->role?->value;

        if ($role === null || ! in_array($role, $roles, true)) {
            return response()->json([
                'message' => 'Akun ini tidak memiliki akses ke fitur tersebut.',
            ], 403);
        }

        return $next($request);
    }
}
