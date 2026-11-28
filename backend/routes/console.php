<?php

use Illuminate\Support\Facades\Schedule;

Schedule::command('analytics:prune')->dailyAt('02:30');
