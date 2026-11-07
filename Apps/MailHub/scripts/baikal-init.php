<?php
// Baïkal bootstrap, run by a setup step (docker run of the Baïkal image) before
// the server starts, on every up. config/baikal.yaml is not written here: it is
// rendered from seed/baikal/baikal.yaml.tmpl (x-compose-app `files`).
//
// First run: creates the SQLite DB with one user, one calendar and one address
// book, so the install wizard never shows.
// Every run: re-syncs the user's password from the app's secrets, so a change
// made from Maison's Security tab takes effect.
$root      = '/var/www/baikal';
$user      = getenv('BAIKAL_USER') ?: 'me';
$userPass  = getenv('BAIKAL_USER_PASSWORD');
$realm     = 'BaikalDAV';   // auth_realm in baikal.yaml
if (!$userPass) { fwrite(STDERR, "BAIKAL_USER_PASSWORD missing\n"); exit(1); }

$dbf  = "$root/Specific/db/db.sqlite";

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
