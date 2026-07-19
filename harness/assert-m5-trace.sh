#!/usr/bin/env bash
# Validates the cross-process invariants emitted by one or more completed M5 handoffs.
set -euo pipefail

fail() {
    echo "M5 trace assertion failed: $*" >&2
    exit 1
}

line_of() {
    local pattern="$1" file="$2"
    grep -n -m1 -E "$pattern" "$file" | cut -d: -f1
}

assert_trace() {
    local log_dir="$1"
    local proxy="$log_dir/proxy.log" source="$log_dir/server-a.log" destination="$log_dir/server-b.log"
    [[ -f "$proxy" && -f "$source" && -f "$destination" ]] \
        || fail "expected proxy.log, server-a.log, and server-b.log under $log_dir"

    transfers=()
    while IFS= read -r completed_transfer; do
        transfers+=("$completed_transfer")
    done < <(sed -nE 's/.*Worldline M5 completed transfer ([0-9a-f-]{36}).*/\1/p' "$proxy" | sort -u)
    (( ${#transfers[@]} > 0 )) || fail "no completed M5 transfer found"

    local transfer
    for transfer in "${transfers[@]}"; do
        [[ $(grep -c "Worldline M5 completed transfer $transfer" "$proxy") -eq 1 ]] \
            || fail "$transfer did not complete exactly once"
        grep -q "Worldline M5 completed transfer $transfer.*client_transition_packets=0" "$proxy" \
            || fail "$transfer exposed a client transition"

        local committed active cleaned complete first_replay
        committed=$(line_of "transfer_id=$transfer.*next_phase=COMMITTED" "$proxy")
        active=$(line_of "transfer_id=$transfer.*next_phase=ACTIVE_DESTINATION" "$proxy")
        cleaned=$(line_of "transfer_id=$transfer.*next_phase=SOURCE_CLEANED" "$proxy")
        complete=$(line_of "Worldline M5 completed transfer $transfer" "$proxy")
        first_replay=$(line_of "Worldline replay transfer=$transfer sequence=" "$proxy")
        [[ -n "$committed" && -n "$active" && -n "$cleaned" && -n "$first_replay" ]] \
            || fail "$transfer is missing proxy phase or replay trace"
        (( committed < active && active <= first_replay && first_replay < cleaned && cleaned < complete )) \
            || fail "$transfer proxy ordering is invalid"
        grep -q "Worldline replay transfer=$transfer sequence=0 has_position=true" "$proxy" \
            || fail "$transfer first replay entry is not the positioned crossing"
        local crossing_x
        crossing_x=$(grep -m1 "Worldline replay transfer=$transfer sequence=0 " "$proxy" \
            | sed -nE 's/.* x=([^ ]+).*/\1/p')
        awk -v x="$crossing_x" 'BEGIN { exit !(x >= 0) }' \
            || fail "$transfer crossing replay is not in the destination partition"

        local freeze commit_source clean_source attach activate_destination processed_replay
        freeze=$(line_of "froze source player=.*transfer=$transfer" "$source")
        commit_source=$(line_of "committed away source player=.*transfer=$transfer" "$source")
        clean_source=$(line_of "cleaned source player=.*transfer=$transfer" "$source")
        attach=$(line_of "attached inert destination player=.*transfer=$transfer" "$destination")
        activate_destination=$(line_of "activated destination player=.*transfer=$transfer" "$destination")
        processed_replay=$(line_of "processed first replay movement .*transfer=$transfer" "$destination")
        [[ -n "$freeze" && -n "$commit_source" && -n "$clean_source" ]] \
            || fail "$transfer is missing source lifecycle trace"
        [[ -n "$attach" && -n "$activate_destination" && -n "$processed_replay" ]] \
            || fail "$transfer is missing destination lifecycle trace"
        (( freeze < commit_source && commit_source < clean_source )) \
            || fail "$transfer source lifecycle is out of order"
        (( attach < activate_destination && activate_destination < processed_replay )) \
            || fail "$transfer destination activated before attachment"

        local source_hash destination_hash
        source_hash=$(grep -m1 "froze source player=.*transfer=$transfer" "$source" \
            | sed -nE 's/.*snapshot_hash=([0-9a-f]{64}).*/\1/p')
        destination_hash=$(grep -m1 "activated destination player=.*transfer=$transfer" "$destination" \
            | sed -nE 's/.*snapshot_hash=([0-9a-f]{64}).*/\1/p')
        [[ -n "$source_hash" && "$source_hash" == "$destination_hash" ]] \
            || fail "$transfer source/destination canonical snapshot hashes differ"

        local source_x destination_x source_authority destination_authority
        source_x=$(grep -m1 "froze source player=.*transfer=$transfer" "$source" \
            | sed -nE 's/.* x=([^ ]+).*/\1/p')
        destination_x=$(grep -m1 "processed first replay movement .*transfer=$transfer" \
            "$destination" | sed -nE 's/.* x=([^ ]+).*/\1/p')
        [[ -n "$source_x" && -n "$destination_x" ]] \
            || fail "$transfer is missing authoritative movement coordinates"
        awk -v source_x="$source_x" -v crossing_x="$crossing_x" \
            -v destination_x="$destination_x" 'BEGIN {
                delta = crossing_x - destination_x;
                if (delta < 0) delta = -delta;
                exit !(source_x < 0 && crossing_x >= 0 && delta < 0.000001)
            }' || fail "$transfer crossing was not applied exactly once by the destination"

        source_authority=$(grep -m1 "committed away source player=.*transfer=$transfer" \
            "$source" | sed -nE 's/.* authority_millis=([0-9]+).*/\1/p')
        destination_authority=$(grep -m1 "activated destination player=.*transfer=$transfer" \
            "$destination" | sed -nE 's/.* authority_millis=([0-9]+).*/\1/p')
        [[ -n "$source_authority" && -n "$destination_authority" ]] \
            || fail "$transfer is missing authority timestamps"
        (( source_authority <= destination_authority )) \
            || fail "$transfer has overlapping source/destination authority"
        [[ $(grep -c "processed first replay movement .*transfer=$transfer" "$destination") -eq 1 ]] \
            || fail "$transfer destination processed the first replay marker more than once"
        ! grep -q "processed first replay movement .*transfer=$transfer" "$source" \
            || fail "$transfer source processed destination replay movement"
    done

    ! grep -Eq 'client_transition_packets=[1-9]|attempted unexpected client transition packet' "$proxy" \
        || fail "client-visible transition output was observed"
    echo "M5 trace assertions passed for ${#transfers[@]} transfer(s)."
}

if [[ "${1:-}" == "--self-test" ]]; then
    fixture="$(mktemp -d)"
    trap 'rm -rf "$fixture"' EXIT
    transfer=00000000-0000-0000-0000-000000000099
    cat >"$fixture/proxy.log" <<EOF
Worldline handoff transfer_id=$transfer next_phase=COMMITTED
Worldline handoff transfer_id=$transfer next_phase=ACTIVE_DESTINATION
Worldline replay transfer=$transfer sequence=0 has_position=true x=0.25 y=64.0 z=0.0
Worldline handoff transfer_id=$transfer next_phase=SOURCE_CLEANED
Worldline M5 completed transfer $transfer for Test epoch=1 route_generation=1 client_transition_packets=0
EOF
    cat >"$fixture/server-a.log" <<EOF
Worldline froze source player=x transfer=$transfer tick=10 snapshot_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa x=-0.25 y=64.0 z=0.0
Worldline committed away source player=x transfer=$transfer tick=11 authority_millis=1000
Worldline cleaned source player=x transfer=$transfer tick=12
EOF
    cat >"$fixture/server-b.log" <<EOF
Worldline attached inert destination player=x transfer=$transfer entity_id=1
Worldline activated destination player=x transfer=$transfer tick=20 snapshot_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa authority_millis=1001
Worldline processed first replay movement player=x transfer=$transfer has_position=true x=0.25 y=64.0 z=0.0 tick=21
EOF
    assert_trace "$fixture" >/dev/null
    sed -i.bak 's/sequence=0/sequence=1/' "$fixture/proxy.log"
    if (assert_trace "$fixture" >/dev/null 2>&1); then
        fail "self-test accepted an invalid replay sequence"
    fi
    echo "M5 trace parser self-test passed."
    exit 0
fi

[[ $# -eq 1 ]] || fail "usage: $0 LOG_DIR | --self-test"
assert_trace "$1"
