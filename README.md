# cpb — safe `curl … | bash`

Goal: run internet install scripts with guarantees instead of trust.

1. Fetch the script once, without executing it, and pin it by sha256.
2. Extract a sandboxing policy from the script text: writable paths, network hosts, root need.
3. Show the policy to the human for approval.
4. Execute exactly the reviewed bytes in a sandbox enforcing that policy at kernel level.

## Status

Only the network layer exists: a kernel-enforced per-IP allowlist, validated on Ubuntu (Linux 6.17, AppArmor userns restriction).
The `cpb` CLI (fetch, policy extraction, approval, filesystem sandbox) does not exist yet.

## Network allowlist: how it works

- `libexec/cpb-netns` runs a command as mapped root in a fresh user + network namespace.
- Ubuntu's AppArmor forbids unprivileged user namespaces; `apparmor/cpb-netns` grants the `userns` permission to the root-owned `/usr/local/libexec/cpb-netns` only (same shape as Ubuntu's `slirp4netns` profile).
- `slirp4netns --disable-host-loopback` attaches `tap0` from outside the namespace.
- Inside, the address is a `/32` with no subnet route; only `/32` routes to the approved IPs exist. No default route, no DNS: names are pinned by the caller.
- The script then runs in `bwrap --cap-drop ALL`, so it can neither add routes nor open raw sockets. Any other destination fails with `ENETUNREACH`, whatever tool the script uses.

Granularity is IP, not hostname: allowing a CDN or `github.com` IP allows everything served from it.

## Install (once, as root)

```sh
sudo apparmor/install.sh
```

Re-run after any change to `libexec/cpb-netns` or `apparmor/cpb-netns`.

## Check

```sh
tests/check_netns.sh            # silent, exit 0: allowed host reachable; 1.1.1.1, DNS, host loopback, route changes refused
LEAKY=1 tests/check_netns.sh    # adds a default route: must print FAIL lines (validates the check)
ALLOW=example.org tests/check_netns.sh
```

Requires `bwrap`, `slirp4netns`, `iproute2`, `curl`.
