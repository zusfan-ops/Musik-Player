<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        RateLimiter::for('login', function (Request $request) {
            $email = strtolower((string) $request->input('email', ''));
            return Limit::perMinute(10)->by($email . '|' . $request->ip());
        });

        RateLimiter::for('password_reset', function (Request $request) {
            return Limit::perMinute(5)->by((string) $request->ip());
        });

        RateLimiter::for('analytics', function (Request $request) {
            $installId = (string) $request->input('installation_id', $request->ip());
            return Limit::perMinute(30)->by($installId);
        });

        RateLimiter::for('feedback', function (Request $request) {
            return Limit::perHour(10)->by((string) $request->ip());
        });

        RateLimiter::for('api', function (Request $request) {
            $key = $request->user()?->id ? 'user:' . $request->user()->id : 'ip:' . $request->ip();
            return Limit::perMinute(120)->by($key);
        });
    }
}
