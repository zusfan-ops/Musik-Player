<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureAdminRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();
        if (!$user || !$user->is_active || !$user->isAdmin()) {
            return redirect()->route('admin.login');
        }

        if (!empty($roles) && !$user->hasAdminRole($roles)) {
            abort(403, 'Anda tidak memiliki izin untuk tindakan ini.');
        }

        return $next($request);
    }
}
