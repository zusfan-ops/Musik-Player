<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rules\Password;

class CreateAdminUser extends Command
{
    protected $signature = 'app:create-admin
                            {--email= : Admin email address}
                            {--name= : Admin display name}
                            {--role=super_admin : Role (super_admin|content_admin|analytics_admin)}';

    protected $description = 'Create an admin user securely without hardcoded default passwords.';

    public function handle(): int
    {
        $email = $this->option('email') ?: $this->ask('Admin email');
        $name = $this->option('name') ?: $this->ask('Admin name');
        $role = $this->option('role');
        $password = $this->secret('Admin password (min 12 chars)');

        $validator = Validator::make(
            compact('email', 'name', 'role', 'password'),
            [
                'email' => ['required', 'email', 'unique:users,email'],
                'name' => ['required', 'string', 'min:2', 'max:100'],
                'role' => ['required', 'in:super_admin,content_admin,analytics_admin'],
                'password' => ['required', Password::min(12)],
            ]
        );

        if ($validator->fails()) {
            foreach ($validator->errors()->all() as $err) {
                $this->error($err);
            }
            return self::FAILURE;
        }

        User::create([
            'name' => $name,
            'email' => strtolower($email),
            'password' => $password,
            'role' => $role,
            'is_active' => true,
            'email_verified_at' => now(),
        ]);

        $this->info("Admin {$email} ({$role}) berhasil dibuat.");
        return self::SUCCESS;
    }
}
