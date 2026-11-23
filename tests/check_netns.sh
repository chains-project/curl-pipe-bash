#!/bin/sh
# Pass/fail check of cpb's kernel-level network allowlist on this host.
# Allowed host: ALLOW (default astral.sh). Denied: 1.1.1.1, DNS, host loopback.
# LEAKY=1 adds a default route: validates that the check detects a leak.
# Prints one FAIL line per broken guarantee; silent and exit 0 when all hold.
set -u
HELPER=${CPB_NETNS:-/usr/local/libexec/cpb-netns}
ALLOW=${ALLOW:-astral.sh}
work=$(mktemp -d)
trap 'kill "$slirp" 2>/dev/null; rm -rf "$work"' EXIT
fail=0; slirp=
no() { echo "FAIL: $*"; fail=1; }

ip=$(getent ahostsv4 "$ALLOW" | awk 'NR==1{print $1}')
[ -n "$ip" ] || { echo "FAIL: cannot resolve $ALLOW"; exit 1; }

# Inside the netns: wait for slirp's tap0, route only the allowed /32, then run
# the probes in a nested bwrap with every capability dropped.
cat > "$work/inner.sh" <<EOF
echo \$\$ > "$work/pid"
i=0; while ! ip link show tap0 >/dev/null 2>&1; do
  i=\$((i+1)); [ \$i -lt 100 ] || { echo "no tap0 after 10s" >&2; exit 1; }; sleep 0.1
done
ip link set lo up
ip link set tap0 up
ip addr add 10.0.2.100/32 dev tap0
ip route add 10.0.2.2/32 dev tap0
ip route add $ip/32 via 10.0.2.2 dev tap0
${LEAKY:+ip route add default via 10.0.2.2 dev tap0}
exec bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
  --unshare-user --uid $(id -u) --gid $(id -g) --cap-drop ALL --die-with-parent \
  sh -c '
    curl -fsS -m 10 -o /dev/null --resolve $ALLOW:443:$ip https://$ALLOW/ && echo allowed_ok
    curl -fsS -m 5 -o /dev/null https://1.1.1.1/ 2>/dev/null && echo denied_reached
    getent hosts example.com >/dev/null 2>&1 && echo dns_reached
    curl -fsS -m 5 -o /dev/null http://10.0.2.2:22/ 2>/dev/null; case \$? in 7|28) ;; *) echo hostlo_reached;; esac
    ip route add 9.9.9.9/32 via 10.0.2.2 dev tap0 2>/dev/null && echo route_added
    true'
EOF

"$HELPER" sh "$work/inner.sh" > "$work/out" 2> "$work/err" &
run=$!
i=0; while [ ! -s "$work/pid" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ -s "$work/pid" ] || { no "helper did not start: $(cat "$work/err")"; exit 1; }
slirp4netns --disable-host-loopback "$(cat "$work/pid")" tap0 > "$work/slirp.log" 2>&1 &
slirp=$!
wait "$run"

grep -q allowed_ok "$work/out" || no "allowed host $ALLOW ($ip) unreachable: $(cat "$work/err")"
grep -q denied_reached "$work/out" && no "unlisted 1.1.1.1 reachable"
grep -q dns_reached "$work/out" && no "DNS resolution works inside sandbox"
grep -q hostlo_reached "$work/out" && no "host loopback reachable via 10.0.2.2"
grep -q route_added "$work/out" && no "sandboxed script could add a route"
exit $fail
