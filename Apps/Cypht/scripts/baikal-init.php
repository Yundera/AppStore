<?php
// Baïkal bootstrap, run by a setup step (docker run of the Baïkal image) before
// the server starts, on every up.
//
// First run: writes config/baikal.yaml and a SQLite DB with one user, one calendar
// and one address book, so the install wizard never shows.
// Every run: re-syncs the admin hash and the user's password from the app's
// secrets, so a change made from Maison's Security tab takes effect.
$root      = '/var/www/baikal';
$user      = getenv('BAIKAL_USER') ?: 'me';
$userPass  = getenv('BAIKAL_USER_PASSWORD');
$adminPass = getenv('BAIKAL_ADMIN_PASSWORD');
$realm     = 'BaikalDAV';
if (!$userPass || !$adminPass) { fwrite(STDERR, "BAIKAL_USER_PASSWORD / BAIKAL_ADMIN_PASSWORD missing\n"); exit(1); }

$yaml = "$root/config/baikal.yaml";
$dbf  = "$root/Specific/db/db.sqlite";
@mkdir("$root/config", 0775, true);
@mkdir(dirname($dbf), 0775, true);

$adminHash = hash('sha256', "admin:$realm:$adminPass");
if (!file_exists($yaml)) {
    file_put_contents($yaml, "system:\n"
        . "    configured_version: '0.10.1'\n"
        . "    timezone: 'Etc/UTC'\n"
        . "    card_enabled: true\n"
        . "    cal_enabled: true\n"
        . "    invite_from: ''\n"
        // Basic, not Digest: what every DAV client and Roundcube's Kolab driver speak.
        . "    dav_auth_type: 'Basic'\n"
        . "    admin_passwordhash: $adminHash\n"
        . "    failed_access_message: 'user %u authentication failure for Baikal'\n"
        . "    auth_realm: $realm\n"
        . "    base_uri: ''\n"
        . "database:\n"
        . "    encryption_key: " . bin2hex(random_bytes(16)) . "\n"
        . "    backend: 'sqlite'\n"
        . "    sqlite_file: '$dbf'\n");
    echo "wrote $yaml\n";
} else {
    $cfg = file_get_contents($yaml);
    $new = preg_replace('/^(\s*admin_passwordhash:\s*).*$/m', '${1}' . $adminHash, $cfg, 1);
    if ($new !== $cfg) { file_put_contents($yaml, $new); }
}

$fresh = !file_exists($dbf);
$db = new PDO("sqlite:$dbf");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
if ($fresh) {
    $db->exec(file_get_contents("$root/Core/Resources/Db/SQLite/db.sql"));
    echo "created $dbf\n";
}

$digest = md5("$user:$realm:$userPass");
$exists = $db->prepare('SELECT COUNT(*) FROM users WHERE username = ?');
$exists->execute([$user]);
if ($exists->fetchColumn() == 0) {
    $p = "principals/$user";
    $db->prepare('INSERT INTO users (username, digesta1) VALUES (?, ?)')->execute([$user, $digest]);
    $ins = $db->prepare('INSERT INTO principals (uri, email, displayname) VALUES (?, ?, ?)');
    $ins->execute([$p, null, $user]);
    $ins->execute(["$p/calendar-proxy-read", null, null]);
    $ins->execute(["$p/calendar-proxy-write", null, null]);
    $db->exec("INSERT INTO calendars (synctoken, components) VALUES (1, 'VEVENT,VTODO')");
    $cid = $db->lastInsertId();
    $db->prepare('INSERT INTO calendarinstances (calendarid, principaluri, access, displayname, uri, description, calendarorder, calendarcolor, timezone, transparent) VALUES (?, ?, 1, ?, ?, ?, 0, ?, ?, 0)')
       ->execute([$cid, $p, 'Calendar', 'default', 'Default calendar', '#3a87ad', null]);
    $db->prepare('INSERT INTO addressbooks (principaluri, displayname, uri, description, synctoken) VALUES (?, ?, ?, ?, 1)')
       ->execute([$p, 'Contacts', 'default', 'Default address book']);
    echo "created DAV user $user\n";
} else {
    $db->prepare('UPDATE users SET digesta1 = ? WHERE username = ?')->execute([$digest, $user]);
}
