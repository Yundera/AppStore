<?php
// Local overrides of include/config_default.inc.php (Yundera AppStore).
//
// The gallery is private as shipped:
// - visitors who are not signed in are sent to the login page;
// - new albums start private, so nothing is listed to a guest anywhere,
//   including through the web API (ws.php), which guest_access alone does not
//   close. Admins are granted every private album they create.
//
// To publish albums to the world later: set an album to "public" in
// Administration > Albums > (album) > Permissions, and change guest_access
// below to true (edit this file from the browser with the "LocalFiles Editor"
// plugin, Administration > Plugins).
$conf['guest_access'] = false;
$conf['newcat_default_status'] = 'private';
