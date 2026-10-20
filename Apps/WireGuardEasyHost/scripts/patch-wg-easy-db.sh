#!/bin/bash
# Step patch-wg-easy-db (at: started, run: always) — see docker-compose.yml.
#
# `run: always`, so it runs after EVERY start, not only the first: it is idempotent (each
# write is guarded) and it then repairs itself — e.g. a host whose uplink device
# changed gets its hooks rewritten on the next start.
# Runs AFTER container startup, against wg-easy's SQLite DB (polls until it is built),
# using the image's own bundled @libsql driver (no sqlite3 CLI present). Five writes:
#
# 1. Default PersistentKeepalive -> 25s. New clients inherit it from the userConfig row
#    (factory 0 = off); v15 dropped the env/INIT var. Only while still at 0, so a manual
#    change in the UI is never clobbered.
#
# 2. Forwarding through Docker's firewall. wg-easy's own PostUp FORWARD accepts go
#    through the image's `iptables`, which is iptables-LEGACY. Docker on the host writes
#    nft, and its nft FORWARD chain has policy DROP. A forwarded packet has to pass both
#    hooks, so the nft drop wins and wg-easy's accepts do nothing: peer-to-peer (wg0->wg0)
#    and full-tunnel (wg0->uplink) traffic is silently dropped on any Docker host.
#    Fix: append rules to PostUp/PostDown that go into DOCKER-USER (Docker never flushes
#    that chain) via iptables-nft, which the image also ships. They live in the hooks, so
#    they are re-applied by every `wg-quick up` (reboots included) and removed on down.
#    Scoped to wg0->wg0 and wg0<->uplink only, NOT a blanket `-i wg0`: that would let
#    a peer route into Docker's container networks and bypass the gateway. Each command
#    ends in `|| true` because wg-quick aborts `up` on a failing hook — a host without
#    DOCKER-USER (e.g. Docker's native nftables backend) keeps a working VPN instead.
#    Appended once (guarded by the DOCKER-USER marker), keeping any user-edited hooks.
#
# 3. Uplink device. The hooks' {{device}} (MASQUERADE for full-tunnel, and rule 2) is
#    hard-coded to `eth0` by wg-easy's first migration, with no env var to change it.
#    Set it to the interface of the host's default route, only while still `eth0`.
#
# 4. MTU -> 1280 instead of wg-easy's 1420: on wg0, as the default for new clients, and
#    on clients still at 1420. 1420 assumes a 1500-byte path; PPPoE, 4G/5G and some ISP
#    boxes carry less, and then every bigger packet is dropped silently: the tunnel
#    pings, SMB authenticates, but a folder listing or a copy hangs forever (seen on a
#    PCS: 1400-byte inner packets passed, 1420 were lost). 1280, the IPv6 minimum, fits
#    any path. Only rows still at 1420 are touched, so a value set in the UI is kept.
#    A client picks up its new MTU the next time its config is downloaded.
#
# 5. TCP MSS clamping on SYNs leaving through wg0. Clients already deployed keep 1420
#    until they re-download their config, and the services they reach (Samba behind a
#    published port, ...) sit on a 1500 bridge that advertises MSS 1460, so those
#    clients would keep sending oversized segments. Clamping to wg0's path MTU (MSS
#    1240 at 1280) fixes TCP for them with nothing to do client-side. Goes into the
#    mangle table via iptables-nft, same delivery and `|| true` as rule 2, with its own
#    TCPMSS guard so boxes that already carry rule 2 get it too.
#
# If 2, 3, 4 or 5 changed anything, the script leaves a marker in the container and the step
# restarts it, so wg-quick re-reads its hooks.

for i in $(seq 1 60); do
  compose exec -w /app/server wgeasyhost node --input-type=module -e '
    import {createClient} from "@libsql/client";
    import {execSync} from "node:child_process";
    const c = createClient({url: "file:/etc/wireguard/wg-easy.db"});
    const n = await c.execute("SELECT count(*) AS n FROM user_configs_table");
    if (Number(n.rows[0].n) < 1) process.exit(3);
    await c.execute("UPDATE user_configs_table SET default_persistent_keepalive=25 WHERE default_persistent_keepalive=0");
    let changed = false;
    // host netns, so this is the host default route
    let up = "";
    try { up = (execSync("ip -4 route show default").toString().match(/ dev (\S+)/) || [])[1] || ""; } catch {}
    if (up && up !== "eth0") {
      const r = await c.execute({sql: "UPDATE interfaces_table SET device=? WHERE name=? AND device=?", args: [up, "wg0", "eth0"]});
      if (r.rowsAffected) { changed = true; console.log("wgeasyhost: uplink device set to " + up); }
    }
    const rules = [
      "DOCKER-USER -i wg0 -o wg0 -j ACCEPT",
      "DOCKER-USER -i wg0 -o {{device}} -j ACCEPT",
      "DOCKER-USER -i {{device}} -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT",
    ];
    const addUp = rules.map(r => " iptables-nft -C " + r + " 2>/dev/null || iptables-nft -I " + r + " || true;").join("");
    const addDown = rules.map(r => " iptables-nft -D " + r + " 2>/dev/null || true;").join("");
    const h = (await c.execute({sql: "SELECT post_up FROM hooks_table WHERE id=?", args: ["wg0"]})).rows[0];
    if (h && !String(h.post_up).includes("DOCKER-USER")) {
      await c.execute({sql: "UPDATE hooks_table SET post_up=post_up||?, post_down=post_down||? WHERE id=?", args: [addUp, addDown, "wg0"]});
      changed = true; console.log("wgeasyhost: DOCKER-USER forward rules added to PostUp/PostDown");
    }
    const mtu = await c.execute({sql: "UPDATE interfaces_table SET mtu=? WHERE name=? AND mtu=?", args: [1280, "wg0", 1420]});
    if (mtu.rowsAffected) { changed = true; console.log("wgeasyhost: wg0 MTU set to 1280"); }
    await c.execute({sql: "UPDATE user_configs_table SET default_mtu=? WHERE id=? AND default_mtu=?", args: [1280, "wg0", 1420]});
    await c.execute({sql: "UPDATE clients_table SET mtu=? WHERE interface_id=? AND mtu=?", args: [1280, "wg0", 1420]});
    const mss = "FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu";
    const h2 = (await c.execute({sql: "SELECT post_up FROM hooks_table WHERE id=?", args: ["wg0"]})).rows[0];
    if (h2 && !String(h2.post_up).includes("TCPMSS")) {
      const mssUp = " iptables-nft -t mangle -C " + mss + " 2>/dev/null || iptables-nft -t mangle -A " + mss + " || true;";
      const mssDown = " iptables-nft -t mangle -D " + mss + " 2>/dev/null || true;";
      await c.execute({sql: "UPDATE hooks_table SET post_up=post_up||?, post_down=post_down||? WHERE id=?", args: [mssUp, mssDown, "wg0"]});
      changed = true; console.log("wgeasyhost: TCP MSS clamping added to PostUp/PostDown");
    }
    if (changed) (await import("node:fs")).writeFileSync("/tmp/wgeasyhost-restart", "");
    else console.log("wgeasyhost: hooks already up to date");
  ' && break
  sleep 2
done
if compose exec wgeasyhost rm /tmp/wgeasyhost-restart 2>/dev/null; then
  compose restart wgeasyhost
fi
