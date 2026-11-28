<?php

use App\Http\Controllers\Admin\AdminController;
use App\Http\Controllers\LandingController;
use Illuminate\Support\Facades\Route;

Route::get('/', [LandingController::class, 'index'])->name('landing');

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
            Route::post('/m3u-sources', [AdminController::class, 'storeM3uSource'])->name('m3u-sources.store');
            Route::post('/m3u-sources/{m3uSource}/toggle', [AdminController::class, 'toggleM3uSource'])->name('m3u-sources.toggle');
            Route::delete('/m3u-sources/{m3uSource}', [AdminController::class, 'deleteM3uSource'])->name('m3u-sources.delete');
        });

        Route::middleware('admin.role:super_admin,analytics_admin')->group(function () {
            Route::post('/feedback/{feedback}/status', [AdminController::class, 'updateFeedbackStatus'])->name('feedback.status');
        });

        Route::middleware('admin.role:super_admin')->group(function () {
            Route::post('/users/{targetUser}/toggle', [AdminController::class, 'toggleUserActive'])->name('users.toggle');
        });
    });
});
