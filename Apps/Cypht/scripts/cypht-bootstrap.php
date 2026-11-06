<?php
// Creates the MCP server's access token, run by the `bootstrap` started step
// (`compose run` of the webmail service, so it is on the app's network):
// logs into cypht-gateway with the app login, which the gateway checks through
// Cypht, creates a read-only personal access token, and prints it as
// CYPHT_GATEWAY_PAT=<token>. Nothing else goes to stdout; progress to stderr.
$gw   = rtrim(getenv('GATEWAY_INTERNAL_URL') ?: 'http://cypht-gateway:8080', '/');
$user = getenv('CYPHT_LOGIN_USER') ?: 'admin';
$pass = getenv('CYPHT_LOGIN_PASSWORD');
if (!$pass) { fwrite(STDERR, "CYPHT_LOGIN_PASSWORD missing\n"); exit(1); }

function call($method, $url, $body = null, $bearer = null) {
    $h = ['Accept: application/json'];
    if ($body !== null) $h[] = 'Content-Type: application/json';
    if ($bearer) $h[] = "Authorization: Bearer $bearer";
    $c = curl_init($url);
    curl_setopt_array($c, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => $h, CURLOPT_TIMEOUT => 60, CURLOPT_CONNECTTIMEOUT => 5]);
    if ($body !== null) curl_setopt($c, CURLOPT_POSTFIELDS, json_encode($body));
    $out = curl_exec($c);
    return [curl_getinfo($c, CURLINFO_HTTP_CODE), $out === false ? null : json_decode($out, true), $out];
}

// The gateway, and Cypht behind it, may still be starting.
$session = null;
for ($i = 0; $i < 40; $i++) {
    [$code, $j] = call('POST', "$gw/api/v1/auth/login", ['username' => $user, 'password' => $pass]);
    if ($code === 200 && !empty($j['access_token'])) { $session = $j['access_token']; break; }
    fwrite(STDERR, "gateway login: HTTP $code, retrying\n");
    sleep(3);
}
if (!$session) { fwrite(STDERR, "gateway login failed\n"); exit(1); }

// No scopes = the gateway's read-only set for assistants (accounts, mail read
// and search, attachments, contacts). No expiry.
[$code, $j, $raw] = call('POST', "$gw/api/v1/tokens", ['name' => 'beacon (mcp)', 'scopes' => []], $session);
if (($code !== 201 && $code !== 200) || empty($j['token'])) { fwrite(STDERR, "token: HTTP $code $raw\n"); exit(1); }
echo "CYPHT_GATEWAY_PAT=" . $j['token'] . "\n";
