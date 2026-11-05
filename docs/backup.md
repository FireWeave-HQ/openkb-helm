# Backup and restore

Knowledge bases are files. OpenKB does not have a separate database.

## What to copy

The chart mounts one volume at `/var/lib/openkb`:

| Path | Contents |
| --- | --- |
| `/var/lib/openkb/kbs/<name>/` | One knowledge base: `raw/`, `wiki/`, `.openkb/`, and a KB-local `.env`. |
| `/var/lib/openkb/home/.config/openkb/` | `global.yaml` (aliases, default KB, optional shared settings) and a global `.env` if the Workbench wrote one. |

`OPENKB_API_TOKEN` is not part of that tree. It lives in the Kubernetes Secret. Back it up with your secret store, or plan to issue a new token and update clients.

A KB `.env` can contain `LLM_API_KEY` if `/init` was called with `api_key`, or if a working-directory `.env` was present when the KB was created. The chart does not create that working-directory file. Treat a backup of the volume as sensitive anyway.

## Snapshot

Use the CSI driver or VolumeSnapshot support in your cluster to snapshot the PersistentVolumeClaim. The claim name for a release called `openkb` is `openkb-data`, unless `fullnameOverride` or `persistence.existingClaim` changed it.

Quiesce writes first if you need a consistent tree. Scale the Deployment to 0, take the snapshot, then scale it back to 1. Compiles and uploads write many files.

## File copy

```bash
kubectl -n openkb exec deploy/openkb -- tar -C /var/lib/openkb -cf - . \
  > openkb-data.tar
```

The container's root filesystem is read-only. `tar` writes to stdout, so it does not need a writable root. `/tmp` is writable if a tool needs scratch space.

Restore onto a new claim, then install with:

```yaml
persistence:
  enabled: true
  existingClaim: openkb-data
```

The directory layout inside the claim must stay `/kbs` and `/home` unless you also change `persistence.kbSubPath` and `persistence.homeSubPath`.

## What uninstall keeps

The chart-managed PVC is annotated `helm.sh/resource-policy: keep`. `helm uninstall` removes the Deployment, Service, ConfigMap, and chart Secret. It leaves the PVC. An `existingClaim` was never owned by the release, so uninstall leaves that claim too.

Delete the claim only when the backup is somewhere else, or when you mean to drop the data:

```bash
kubectl delete pvc -n openkb openkb-data
```

## What a restore does not include

- The bearer token, unless you backed up the Secret separately.
- In-flight watcher state. Watchers are memory in the OpenKB process (`WatchRegistry`). After a restart, start them again from the Workbench or `POST /api/v1/watch/start`.
- Chat and wiki files that were already flushed to the volume are included. Those sessions live under the knowledge base directory.
