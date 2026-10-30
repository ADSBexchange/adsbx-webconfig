<?php
session_start();
header('Content-Type: application/json');
header('Cache-Control: no-store');
if ($_SESSION['authenticated'] != 1) {
    http_response_code(403);
    echo '{"error":"not authenticated"}';
    exit;
}
require 'steps.php';

$running = trim((string) shell_exec("pgrep -f '^/bin/bash /run/bg-update.sh$' 2>/dev/null")) !== '';
$result = null;
if (!$running) {
    $last = @file_get_contents('/adsbexchange/update-result.json');
    $last = $last ? json_decode($last, true) : null;
    if (is_array($last) && isset($last['result'])) {
        $result = $last['result'];
    }
}
$lines = @file('/adsbexchange/adsbx-update.log');
$steps = parse_update_steps($lines ? $lines : array(), !$running);
echo json_encode(array('running' => $running, 'result' => $result, 'steps' => $steps));
