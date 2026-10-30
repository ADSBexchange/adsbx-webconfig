<?php
// Progress markers written by the update scripts: "== step <id> <start|ok|failed> (<time>)[: <message>]"

function update_step_label($id) {
    $labels = array(
        'apt-update' => 'Package lists',
        'feed-software' => 'Feed software',
        'packages' => 'Build dependencies',
        'skeleton' => 'System files and services',
        'readsb' => 'readsb (ADS-B decoder)',
        'stats' => 'Stats client',
        'mlat-client' => 'mlat-client',
        'tar1090' => 'tar1090 (map)',
        'config' => 'Feeder configuration',
        'web-ui' => 'Web UI',
        'reboot' => 'Reboot',
    );
    return isset($labels[$id]) ? $labels[$id] : $id;
}

// Returns the steps in the order they started: id, label, state (running, ok, failed), started, finished, message.
// When $finished is true, a step that never reported ok or failed is marked failed.
function parse_update_steps($lines, $finished) {
    $steps = array();
    foreach ($lines as $line) {
        if (!preg_match('/^== step (\S+) (start|ok|failed)(?: \((\d\d:\d\d:\d\d)\))?(?:: (.*))?$/', trim($line), $m)) {
            continue;
        }
        $id = $m[1];
        $time = isset($m[3]) ? $m[3] : '';
        $message = isset($m[4]) ? $m[4] : '';
        if ($m[2] === 'start') {
            $steps[$id] = array('id' => $id, 'label' => update_step_label($id), 'state' => 'running',
                                'started' => $time, 'finished' => '', 'message' => '');
        } elseif (isset($steps[$id])) {
            $steps[$id]['state'] = $m[2];
            $steps[$id]['finished'] = $time;
            $steps[$id]['message'] = $message;
        }
    }
    if ($finished) {
        foreach ($steps as &$step) {
            if ($step['state'] === 'running' && $step['id'] !== 'reboot') {
                $step['state'] = 'failed';
                $step['message'] = 'did not finish';
            }
        }
        unset($step);
    }
    return array_values($steps);
}
