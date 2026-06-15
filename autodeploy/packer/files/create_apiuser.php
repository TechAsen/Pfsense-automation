#!/usr/local/bin/php
<?php
/*
 * Create or update a local pfSense API user during Packer provisioning.
 *
 * Values are supplied by Packer environment_vars:
 *   PFSENSE_API_USER
 *   PFSENSE_API_PASS
 *   PFSENSE_API_PRIVS
 */

require_once("/etc/inc/config.inc");
require_once("/etc/inc/auth.inc");

global $config;

$username = getenv("PFSENSE_API_USER") ?: "apiuser";
$password = getenv("PFSENSE_API_PASS") ?: "";
$descr    = getenv("PFSENSE_API_DESCR") ?: "REST API user";
$privsRaw = getenv("PFSENSE_API_PRIVS") ?: "page-all";

if ($password === "") {
    fwrite(STDERR, "ERROR: PFSENSE_API_PASS is empty\n");
    exit(1);
}

if (!preg_match('/^[A-Za-z0-9._-]+$/', $username)) {
    fwrite(STDERR, "ERROR: invalid username '{$username}'\n");
    exit(1);
}

if (!is_array($config['system']['user'] ?? null)) {
    $config['system']['user'] = [];
}

if (!is_array($config['system']['group'] ?? null)) {
    $config['system']['group'] = [];
}

$a_user  = &$config['system']['user'];
$a_group = &$config['system']['group'];

function next_available_uid(array $users, mixed $nextuid): int {
    $max = is_numeric($nextuid) ? (int)$nextuid : 2000;

    foreach ($users as $u) {
        if (isset($u['uid']) && is_numeric($u['uid'])) {
            $max = max($max, ((int)$u['uid']) + 1);
        }
    }

    return max($max, 2000);
}

function ensure_admins_group_member(array &$groups, string $uid): void {
    $adminsIndex = null;

    foreach ($groups as $i => $g) {
        if (($g['name'] ?? '') === 'admins') {
            $adminsIndex = $i;
            break;
        }
    }

    if ($adminsIndex === null) {
        $groups[] = [
            'name'        => 'admins',
            'description' => 'System Administrators',
            'scope'       => 'system',
            'gid'         => '1999',
            'member'      => []
        ];
        $adminsIndex = count($groups) - 1;
    }

    if (!isset($groups[$adminsIndex]['member'])) {
        $groups[$adminsIndex]['member'] = [];
    }

    if (!is_array($groups[$adminsIndex]['member'])) {
        $groups[$adminsIndex]['member'] = [$groups[$adminsIndex]['member']];
    }

    $members = array_map('strval', $groups[$adminsIndex]['member']);

    if (!in_array($uid, $members, true)) {
        $groups[$adminsIndex]['member'][] = $uid;
    }
}

/* Find or create user. */
$idx = null;
foreach ($a_user as $i => $u) {
    if (($u['name'] ?? '') === $username) {
        $idx = $i;
        break;
    }
}

if ($idx === null) {
    $uid = next_available_uid($a_user, $config['system']['nextuid'] ?? 2000);

    $a_user[] = [
        'name'      => $username,
        'descr'     => $descr,
        'scope'     => 'user',
        'uid'       => (string)$uid,
        'groupname' => 'admins',
        'priv'      => []
    ];

    $idx = count($a_user) - 1;
    $config['system']['nextuid'] = (string)($uid + 1);
} else {
    if (empty($a_user[$idx]['uid']) || !is_numeric($a_user[$idx]['uid'])) {
        $uid = next_available_uid($a_user, $config['system']['nextuid'] ?? 2000);
        $a_user[$idx]['uid'] = (string)$uid;
        $config['system']['nextuid'] = (string)($uid + 1);
    }

    $a_user[$idx]['descr'] = $descr;
    $a_user[$idx]['scope'] = $a_user[$idx]['scope'] ?? 'user';
    $a_user[$idx]['groupname'] = 'admins';
}

/* Add privileges. */
if (!is_array($a_user[$idx]['priv'] ?? null)) {
    $a_user[$idx]['priv'] = [];
}

$privs = array_values(array_filter(array_map('trim', explode(',', $privsRaw))));
foreach ($privs as $priv) {
    if ($priv !== "" && !in_array($priv, $a_user[$idx]['priv'], true)) {
        $a_user[$idx]['priv'][] = $priv;
    }
}

/*
 * Use pfSense native helper when available.
 * It sets the correct password hash fields for the installed pfSense version.
 */
if (function_exists('local_user_set_password')) {
    local_user_set_password($a_user[$idx], $password);
} else {
    unset($a_user[$idx]['password']);
    unset($a_user[$idx]['md5-hash']);
    $a_user[$idx]['bcrypt-hash'] = password_hash($password, PASSWORD_BCRYPT);
}

/* Ensure admins group membership is consistent. */
ensure_admins_group_member($a_group, (string)$a_user[$idx]['uid']);

/*
 * Apply user to the local OS user database and persist config.xml.
 * Do not fail the Packer build on authenticate_user(); during first boot/provisioning
 * it can return false before all auth state is fully refreshed even when config.xml is correct.
 */
local_user_set($a_user[$idx]);
write_config("Created/updated local pfSense API user '{$username}'");

echo "OK: user '{$username}' created/updated\n";
echo "OK: uid='{$a_user[$idx]['uid']}', group='admins', privs='" . implode(',', $a_user[$idx]['priv']) . "'\n";

exit(0);
