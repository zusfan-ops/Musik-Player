<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\SyncFavoriteResource;
use App\Http\Resources\SyncPlaylistResource;
use App\Http\Resources\SyncSettingResource;
use App\Models\Store;
use App\Models\User;
use App\Models\UserDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password as PasswordRule;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:100'],
            'email' => ['required', 'string', 'email', 'max:190', 'unique:users,email'],
            'phone' => ['nullable', 'string', 'max:30'],
            'password' => ['required', 'string', PasswordRule::min(8)],
            'device_name' => ['nullable', 'string', 'max:120'],
            'platform' => ['nullable', 'string', 'in:android,android_tv,windows,linux,macos,ios'],
            'app_version' => ['nullable', 'string', 'max:32'],
            'activate_store' => ['sometimes', 'boolean'],
            'store_name' => ['nullable', 'string', 'min:2', 'max:120', 'required_if:activate_store,true'],
            'store_slug' => [
                'nullable',
                'string',
                'min:3',
                'max:64',
                'regex:/^[a-z0-9\-]+$/',
                Rule::notIn(Store::RESERVED_SLUGS),
                'unique:stores,slug',
                'required_if:activate_store,true',
            ],
            'store_type' => ['nullable', Rule::in(Store::TYPES)],
            'store_address' => ['nullable', 'string', 'max:300'],
            'tables_count' => ['nullable', 'integer', 'min:0', 'max:200'],
        ]);

        $user = DB::transaction(function () use ($data) {
            $user = User::create([
                'name' => $data['name'],
                'email' => strtolower($data['email']),
                'phone' => isset($data['phone']) ? trim((string) $data['phone']) ?: null : null,
                'password' => $data['password'],
                'role' => User::ROLE_USER,
                'is_active' => true,
            ]);

            if (!empty($data['activate_store']) && !empty($data['store_name']) && !empty($data['store_slug'])) {
                $storeType = $data['store_type'] ?? 'umum';
                Store::create([
                    'user_id' => $user->id,
                    'name' => trim((string) $data['store_name']),
                    'slug' => strtolower(trim((string) $data['store_slug'])),
                    'store_type' => $storeType,
                    'address' => $data['store_address'] ?? null,
                    'whatsapp_number' => $user->phone,
                    'tables_count' => $data['tables_count'] ?? ($storeType === 'coffeeshop' ? 10 : 0),
                    'is_active' => true,
                ]);
            }

            return $user;
        });

        if (config('mail.default') && config('mail.default') !== 'log' && config('mail.default') !== 'array') {
            try {
                $user->sendEmailVerificationNotification();
            } catch (\Throwable) {
                // Non-blocking when SMTP is not yet configured
            }
        }

        [$plainTextToken, $device] = $this->issueTokenAndDevice($user, $data);

        return response()->json([
            'token' => $plainTextToken,
            'token_type' => 'Bearer',
            'user' => $this->formatUser($user),
            'device' => $device,
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'string', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:120'],
            'platform' => ['nullable', 'string', 'in:android,android_tv,windows,linux,macos,ios'],
            'app_version' => ['nullable', 'string', 'max:32'],
        ]);

        $user = User::where('email', strtolower($data['email']))->first();
        if (!$user || !Hash::check($data['password'], $user->password)) {
            return response()->json([
                'message' => 'Email atau kata sandi salah.',
                'error_code' => 'INVALID_CREDENTIALS',
            ], 401);
        }

        if ($user->isSuspended()) {
            $reason = $user->suspension_reason ? " ({$user->suspension_reason})" : '';
            return response()->json([
                'message' => "Akun sedang disuspend / dinonaktifkan{$reason}.",
                'error_code' => 'ACCOUNT_SUSPENDED',
            ], 403);
        }

        [$plainTextToken, $device] = $this->issueTokenAndDevice($user, $data);

        return response()->json([
            'token' => $plainTextToken,
            'token_type' => 'Bearer',
            'user' => $this->formatUser($user),
            'device' => $device,
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();
        if ($token) {
            UserDevice::where('user_id', $user->id)
                ->where('token_id', $token->id)
                ->update(['revoked_at' => now()]);
            $token->delete();
        }

        return response()->json(['message' => 'Berhasil keluar.']);
    }

    public function refresh(Request $request): JsonResponse
    {
        $user = $request->user();
        $oldToken = $user->currentAccessToken();
        $deviceInfo = UserDevice::where('user_id', $user->id)
            ->where('token_id', $oldToken?->id)
            ->first();

        if ($oldToken) {
            $oldToken->delete();
        }

        $deviceName = $deviceInfo?->device_name ?? 'MediaCenter Client';
        $newToken = $user->createToken($deviceName);
        if ($deviceInfo) {
            $deviceInfo->update([
                'token_id' => $newToken->accessToken->id,
                'last_seen_at' => now(),
            ]);
        }

        return response()->json([
            'token' => $newToken->plainTextToken,
            'token_type' => 'Bearer',
        ]);
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $request->validate(['email' => ['required', 'email']]);
        try {
            Password::sendResetLink(['email' => strtolower($request->string('email'))]);
        } catch (\Throwable) {
            // Do not leak SMTP configuration details
        }

        return response()->json([
            'message' => 'Jika email terdaftar, instruksi reset kata sandi telah dikirim.',
        ]);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string'],
            'email' => ['required', 'email'],
            'password' => ['required', 'string', PasswordRule::min(8), 'confirmed'],
        ]);

        $status = Password::reset(
            [
                'email' => strtolower($data['email']),
                'password' => $data['password'],
                'password_confirmation' => $request->input('password_confirmation'),
                'token' => $data['token'],
            ],
            function (User $user, string $password) {
                $user->forceFill(['password' => $password])->save();
                $user->tokens()->delete();
            }
        );

        if ($status !== Password::PASSWORD_RESET) {
            return response()->json([
                'message' => 'Token reset tidak valid atau sudah kedaluwarsa.',
                'error_code' => 'INVALID_RESET_TOKEN',
            ], 422);
        }

        return response()->json(['message' => 'Kata sandi berhasil diperbarui.']);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'data' => $this->formatUser($request->user()),
        ]);
    }

    public function updateMe(Request $request): JsonResponse
    {
        $user = $request->user();
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'min:2', 'max:100'],
            'analytics_opted_in' => ['sometimes', 'boolean'],
            'current_password' => ['required_with:new_password', 'string'],
            'new_password' => ['sometimes', 'string', PasswordRule::min(8)],
        ]);

        if (isset($data['new_password'])) {
            if (!Hash::check($data['current_password'], $user->password)) {
                return response()->json([
                    'message' => 'Kata sandi saat ini tidak cocok.',
                    'error_code' => 'INVALID_CURRENT_PASSWORD',
                ], 422);
            }
            $user->password = $data['new_password'];
        }

        if (isset($data['name'])) {
            $user->name = $data['name'];
        }
        if (array_key_exists('analytics_opted_in', $data)) {
            $user->analytics_opted_in = $data['analytics_opted_in'];
        }
        $user->save();

        return response()->json([
            'data' => $this->formatUser($user),
        ]);
    }

    public function devices(Request $request): JsonResponse
    {
        $devices = $request->user()
            ->devices()
            ->whereNull('revoked_at')
            ->orderByDesc('last_seen_at')
            ->get();

        return response()->json(['data' => $devices]);
    }

    public function revokeDevice(Request $request, UserDevice $device): JsonResponse
    {
        $user = $request->user();
        if ($device->user_id !== $user->id) {
            return response()->json(['message' => 'Akses ditolak.'], 403);
        }

        if ($device->token_id) {
            $user->tokens()->where('id', $device->token_id)->delete();
        }
        $device->update(['revoked_at' => now()]);

        return response()->json(['message' => 'Sesi perangkat dicabut.']);
    }

    public function exportData(Request $request): JsonResponse
    {
        $user = $request->user();
        $playlists = $user->syncedPlaylists()->with('items')->get();
        $favorites = $user->syncedFavorites()->get();
        $setting = $user->syncedSetting()->first();

        return response()->json([
            'exported_at' => now()->toIso8601String(),
            'user' => $this->formatUser($user),
            'playlists' => SyncPlaylistResource::collection($playlists),
            'favorites' => SyncFavoriteResource::collection($favorites),
            'settings' => $setting ? new SyncSettingResource($setting) : null,
        ]);
    }

    public function deleteAccount(Request $request): JsonResponse
    {
        $user = $request->user();
        DB::transaction(function () use ($user) {
            $user->tokens()->delete();
            $user->delete();
        });

        return response()->json([
            'message' => 'Akun dan seluruh data sinkronisasi telah dihapus.',
        ]);
    }

    private function issueTokenAndDevice(User $user, array $data): array
    {
        $deviceName = $data['device_name'] ?? 'MediaCenter Client';
        $platform = $data['platform'] ?? 'android';
        $appVersion = $data['app_version'] ?? null;

        $maxDevices = config('mediacenter.max_devices_per_user', 5);
        $activeDevices = $user->devices()
            ->whereNull('revoked_at')
            ->orderBy('last_seen_at')
            ->get();

        if ($activeDevices->count() >= $maxDevices) {
            $oldest = $activeDevices->first();
            if ($oldest) {
                if ($oldest->token_id) {
                    $user->tokens()->where('id', $oldest->token_id)->delete();
                }
                $oldest->update(['revoked_at' => now()]);
            }
        }

        $token = $user->createToken($deviceName);
        $device = UserDevice::create([
            'user_id' => $user->id,
            'token_id' => $token->accessToken->id,
            'device_name' => $deviceName,
            'platform' => $platform,
            'app_version' => $appVersion,
            'last_seen_at' => now(),
        ]);

        return [$token->plainTextToken, $device];
    }

    private function formatUser(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'role' => $user->role,
            'sync_revision' => $user->sync_revision,
            'analytics_opted_in' => $user->analytics_opted_in,
            'email_verified' => $user->email_verified_at !== null,
            'created_at' => $user->created_at?->toIso8601String(),
        ];
    }
}
