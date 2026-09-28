# Kubelet extraMounts / extraConfig

**`topf apply` cannot currently be run against `k8s-bee-s1`, `k8s-bee-s2`,
or `k8s-min-s3` at all — for any change, not just kubelet — until one of
the mitigations below happens.** This is more serious than "one field is
unmanaged"; it blocks the whole config-management cutover to topf for
these 3 nodes.

## Why

Talos has no typed-document equivalent for `.machine.kubelet.extraMounts`
yet ([siderolabs/talos#14365][1]), and these 3 nodes already have
`.machine.kubelet` populated from their pre-1.14 (talhelper) provisioning.
`topf apply` submits the whole resolved document set as one atomic
replace (confirmed: it's a single RPC call per node, all-or-nothing, not
a partial/incremental merge), and Talos unconditionally rejects that
whole submission if any legacy field is already populated — regardless of
whether the new value matches the old one:

```
kubelet config is already set in v1alpha1 config (.machine.kubelet)
```

We deliberately keep `.machine.kubelet` declared correctly in
`talos/all/30-kubelet.yaml` and `talos/node/<hostname>/disks.yaml` rather
than omitting it: omitting it "fixes" the validation error, but since
`topf apply` replaces the whole config, omitting a field that's actually
live means the apply would **delete** it outright (confirmed via
`--dry-run` — it showed the entire kubelet block, including the
`/var/openebs/local` and `/var/lib/longhorn` mounts Longhorn/OpenEBS
depend on, being removed). Failing closed (blocked apply, nothing
touched) is far better than failing open (silent deletion of live
storage mounts).

## The actual fixes (pick one, eventually)

1. **Wait for Talos to add typed `extraMounts` support**, then convert
   these files to that typed document — no live-node friction at that
   point, since it'd be a normal typed-doc merge like everything else in
   `talos/all/` already is.
2. **Reset and re-bootstrap each node from scratch** (`topf reset` +
   fresh `topf apply` on a wiped node). A freshly-provisioned node has no
   pre-existing legacy value to conflict with, so `topf render`/`apply`
   works cleanly (verified locally in an earlier validation pass). This
   is the Talos-native migration path, but invasive: one node at a time,
   full reinstall, matching what we did for k8s-bee-s1/s2/s3 disk/version
   upgrades but more disruptive (etcd re-join, node re-provision).

## In the meantime: changing a mount

Use `talosctl patch machineconfig` (a separate, merge-based RPC — proven
via `--dry-run` to work on these live nodes, unlike `topf apply`). It
merges lists by **appending**, not by replacing or deduplicating matching
entries, so include only the **new** entries you want to add, not the
full existing list, or you'll get duplicate mount entries for the same
destination:

```bash
talosctl patch machineconfig -n <node-ip> --dry-run -p @- <<'EOF'
machine:
  kubelet:
    extraMounts:
      - destination: /var/mnt/new-disk
        type: bind
        source: /var/mnt/new-disk
        options: [bind, rshared, rw]
EOF
```

Review the diff, then re-run without `--dry-run`. Afterwards, update the
corresponding `<hostname>.yaml` file here (and `talos/all/30-kubelet.yaml`
/ `talos/node/<hostname>/disks.yaml`, which stay the source of truth for
what *should* be there) to match the new live state.

[1]: https://github.com/siderolabs/talos/issues/14365
