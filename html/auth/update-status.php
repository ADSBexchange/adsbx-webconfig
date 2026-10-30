<?php
session_start();
header('Content-Type: application/json');
header('Cache-Control: no-store');
if ($_SESSION['authenticated'] != 1) {
    http_response_code(403);
    echo '{"error":"not authenticated"}';
    exit;
}

$arguments = isset($_GET['check']) ? ' --check' : '';
$output = shell_exec('sudo /adsbexchange/webconfig/helpers/update-status.sh' . $arguments . ' 2>/dev/null');
if ($output === null || $output === '') {
    http_response_code(500);
    echo '{"error":"status helper failed"}';
    exit;
}
echo $output;
