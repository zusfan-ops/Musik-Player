<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    public const ROLE_USER = 'user';
    public const ROLE_SUPER_ADMIN = 'super_admin';
    public const ROLE_CONTENT_ADMIN = 'content_admin';
    public const ROLE_ANALYTICS_ADMIN = 'analytics_admin';

    protected $fillable = [
        'name',
        'email',
        'phone',
        'address',
        'password',
        'role',
        'is_active',
        'suspended_until',
        'suspension_reason',
        'sync_revision',
        'analytics_opted_in',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_active' => 'boolean',
            'suspended_until' => 'datetime',
            'sync_revision' => 'integer',
            'analytics_opted_in' => 'boolean',
        ];
    }

    public function isSuspended(): bool
    {
        if (!$this->is_active) {
            return true;
        }
        return $this->suspended_until !== null && $this->suspended_until->isFuture();
    }

    public function store(): HasOne
    {
        return $this->hasOne(Store::class);
    }

    public function isAdmin(): bool
    {
        return in_array($this->role, [
            self::ROLE_SUPER_ADMIN,
            self::ROLE_CONTENT_ADMIN,
            self::ROLE_ANALYTICS_ADMIN,
        ], true);
    }

    public function hasAdminRole(array $roles): bool
    {
        return $this->role === self::ROLE_SUPER_ADMIN || in_array($this->role, $roles, true);
    }

    public function devices(): HasMany
    {
        return $this->hasMany(UserDevice::class);
    }

    public function syncedPlaylists(): HasMany
    {
        return $this->hasMany(SyncedPlaylist::class);
    }

    public function syncedFavorites(): HasMany
    {
        return $this->hasMany(SyncedFavorite::class);
    }

    public function syncedSetting(): HasOne
    {
        return $this->hasOne(SyncedSetting::class);
    }
}
