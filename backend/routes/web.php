<?php

use App\Http\Controllers\Admin\AdminController;
use Illuminate\Support\Facades\Route;

Route::get('/', fn () => response()->json(['service' => 'MediaCenter API', 'docs' => '/api/v1/app-config']));

Route::prefix('admin')->name('admin.')->group(function () {
    Route::get('/login', [AdminController::class, 'showLogin'])->name('login');
    Route::post('/login', [AdminController::class, 'login'])
        ->middleware('throttle:login')
        ->name('login.submit');

    Route::middleware(['auth', 'admin.role'])->group(function () {
        Route::get('/', [AdminController::class, 'dashboard'])->name('dashboard');
        Route::post('/logout', [AdminController::class, 'logout'])->name('logout');

        Route::middleware('admin.role:super_admin,content_admin')->group(function () {
            Route::post('/announcements', [AdminController::class, 'storeAnnouncement'])->name('announcements.store');
            Route::post('/announcements/{announcement}/toggle', [AdminController::class, 'toggleAnnouncement'])->name('announcements.toggle');
            Route::delete('/announcements/{announcement}', [AdminController::class, 'deleteAnnouncement'])->name('announcements.delete');
            Route::post('/releases', [AdminController::class, 'storeRelease'])->name('releases.store');
        });

        Route::middleware('admin.role:super_admin,analytics_admin')->group(function () {
            Route::post('/feedback/{feedback}/status', [AdminController::class, 'updateFeedbackStatus'])->name('feedback.status');
        });

        Route::middleware('admin.role:super_admin')->group(function () {
            Route::post('/users/{targetUser}/toggle', [AdminController::class, 'toggleUserActive'])->name('users.toggle');
        });
    });
});
