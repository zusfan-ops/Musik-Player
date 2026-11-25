<?php
$apks = glob(__DIR__ . '/*.apk');
if (!empty($apks)) {
    $selected = $apks[0];
    foreach ($apks as $apk) {
        if (stripos($apk, 'arm64') !== false) {
            $selected = $apk;
            break;
        }
    }
    header('Location: ' . basename($selected), true, 302);
    exit;
}
header('Location: ../', true, 302);
exit;
