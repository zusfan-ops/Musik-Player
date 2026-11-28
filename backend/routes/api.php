<?php

use App\Http\Controllers\Api\V1\AnalyticsController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\FeedbackController;
use App\Http\Controllers\Api\V1\PublicController;
use App\Http\Controllers\Api\V1\SyncController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    // Public, unauthenticated endpoints (guest-first)
    Route::get('/health', [PublicController::class, 'health']);
    Route::get('/app-config', [PublicController::class, 'appConfig']);
    Route::get('/announcements', [PublicController::class, 'announcements']);
    Route::get('/releases/latest', [PublicController::class, 'latestRelease']);

    Route::post('/analytics/events', [AnalyticsController::class, 'storeEvents'])
        ->middleware('throttle:analytics');
    Route::delete('/analytics/installation/{installationId}', [AnalyticsController::class, 'deleteInstallationEvents'])
        ->middleware('throttle:analytics');

    Route::post('/feedback', [FeedbackController::class, 'store'])
        ->middleware('throttle:feedback');

    // Optional authentication
    Route::prefix('auth')->group(function () {
        Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:login');
        Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:login');
        Route::post('/forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:password_reset');
        Route::post('/reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:password_reset');

        Route::middleware(['auth:sanctum', 'throttle:api'])->group(function () {
            Route::post('/logout', [AuthController::class, 'logout']);
            Route::post('/refresh', [AuthController::class, 'refresh']);
        });
    });

    // Authenticated account & opt-in sync
    Route::middleware(['auth:sanctum', 'throttle:api'])->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::patch('/me', [AuthController::class, 'updateMe']);
        Route::get('/me/devices', [AuthController::class, 'devices']);
        Route::delete('/me/devices/{device}', [AuthController::class, 'revokeDevice']);
        Route::get('/me/export', [AuthController::class, 'exportData']);
        Route::delete('/me', [AuthController::class, 'deleteAccount']);

        Route::get('/sync', [SyncController::class, 'index']);
        Route::put('/sync', [SyncController::class, 'upsert']);
        Route::delete('/sync', [SyncController::class, 'destroySyncData']);

        Route::get('/playlists', [SyncController::class, 'playlistsIndex']);
        Route::post('/playlists', [SyncController::class, 'playlistsStore']);
        Route::get('/playlists/{playlist}', [SyncController::class, 'playlistsShow']);
        Route::put('/playlists/{playlist}', [SyncController::class, 'playlistsUpdate']);
        Route::delete('/playlists/{playlist}', [SyncController::class, 'playlistsDestroy']);
    });
});
