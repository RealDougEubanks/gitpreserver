# Storage backends

GitPreserver uses rclone to sync backups, which means any of rclone's 70+ supported backends work without code changes. Configure the remote in `rclone/rclone.conf`, then set `GITPRESERVER_RCLONE_REMOTE` to its name.

---

## Backblaze B2 (recommended)

B2 is the recommended default: cheapest object storage at scale (~$0.006/GB/month), no egress fees when used with rclone, and straightforward key management.

### Setup

1. Log in to [backblaze.com](https://www.backblaze.com) and go to **App Keys**
2. Click **Add a New Application Key**
3. Give it a name (e.g. `gitpreserver`)
4. Set **Allowed Buckets** to a specific bucket, or leave blank for all
5. Set **Type of Access** to **Read and Write**
6. Click **Create New Key** and copy both the **keyID** and **applicationKey** immediately

Create a bucket:
1. Go to **Buckets → Create a Bucket**
2. Name it `gitpreserver-backups` (or your preferred name)
3. Keep **Files in Bucket** as **Private**

Configure `rclone/rclone.conf`:

```ini
[b2-remote]
type = b2
account = YOUR_ACCOUNT_ID
key = YOUR_APPLICATION_KEY
hard_delete = false
```

Set in `.env`:

```bash
GITPRESERVER_RCLONE_REMOTE=b2-remote
GITPRESERVER_RCLONE_PATH=gitpreserver-backups
```

---

## AWS S3

Requires an IAM user with `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket` permissions on the target bucket.

```ini
[s3-remote]
type = s3
provider = AWS
access_key_id = YOUR_ACCESS_KEY_ID
secret_access_key = YOUR_SECRET_ACCESS_KEY
region = us-east-1
```

For **Cloudflare R2** (S3-compatible, no egress fees):

```ini
[r2-remote]
type = s3
provider = Cloudflare
access_key_id = YOUR_R2_ACCESS_KEY_ID
secret_access_key = YOUR_R2_SECRET_ACCESS_KEY
endpoint = https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
```

For **Wasabi**:

```ini
[wasabi-remote]
type = s3
provider = Wasabi
access_key_id = YOUR_WASABI_ACCESS_KEY
secret_access_key = YOUR_WASABI_SECRET_KEY
endpoint = https://s3.wasabisys.com
```

---

## Google Drive

Run the interactive config to complete OAuth:

```bash
docker run --rm -it \
  -v "$(pwd)/rclone:/root/.config/rclone" \
  dougeubanks/gitpreserver \
  rclone config
```

Select **n** (new remote), name it `gdrive`, choose type `drive`, and follow the OAuth prompts in your browser. Paste the resulting config block into `rclone.conf`.

---

## Microsoft OneDrive

Same process as Google Drive:

```bash
docker run --rm -it \
  -v "$(pwd)/rclone:/root/.config/rclone" \
  dougeubanks/gitpreserver \
  rclone config
```

Select type `onedrive` and follow the OAuth flow.

---

## MEGA

```ini
[mega]
type = mega
user = your@email.com
pass = RCLONE_OBSCURED_PASSWORD
```

Generate the obscured password:

```bash
docker run --rm dougeubanks/gitpreserver rclone obscure 'your-mega-password'
```

---

## SMB / CIFS (NAS share, Windows file server)

```ini
[smb-nas]
type = smb
host = 192.168.1.10
user = your_smb_user
pass = RCLONE_OBSCURED_PASSWORD
port = 445
```

Generate the obscured password:

```bash
docker run --rm dougeubanks/gitpreserver rclone obscure 'your-smb-password'
```

---

## Local filesystem

Use local mode when the host volume IS your storage — for example, a NAS where you manage offsite sync separately.

```ini
[local]
type = local
nounc = true
```

Or leave `GITPRESERVER_RCLONE_REMOTE` blank in `.env` to skip remote sync entirely and keep backups only on the mounted volume.

---

## SFTP

```ini
[sftp-remote]
type = sftp
host = your.server.example.com
user = your_user
port = 22
key_file = /root/.ssh/id_rsa
```

Mount your SSH key into the container:

```yaml
# docker-compose.yml override
services:
  sync:
    volumes:
      - ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro
```

---

## Testing your remote

Before running a full backup, verify rclone can reach the remote:

```bash
docker run --rm \
  -v "$(pwd)/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro" \
  dougeubanks/gitpreserver \
  rclone lsd b2-remote:
```

Replace `b2-remote` with your remote name. If this lists your bucket or directory, the remote is configured correctly.

---

## Multiple destinations

Set `GITPRESERVER_RCLONE_REMOTE` to a comma-separated list to sync the same backup to several remotes in one run:

```bash
GITPRESERVER_RCLONE_REMOTE=b2-remote,s3-remote,nas-remote
```

Each remote is synced in turn. If one fails, GitPreserver logs the error, skips it, and keeps going with the rest — a single broken destination does not stop the others. Local retention pruning still runs after the sync loop regardless of any failure. The run exits non-zero if any remote failed, and the list of failed remotes is written to `<backup_dir>/.gitpreserver-failed-remotes` so the notification layer can report it.

### Multiple destinations with encryption

When `GITPRESERVER_ENCRYPT=true`, `GITPRESERVER_CRYPT_REMOTE` must list one crypt remote for every plain remote, in the same order — they are paired by position. The first crypt remote wraps the first plain remote, the second wraps the second, and so on:

```bash
GITPRESERVER_ENCRYPT=true
GITPRESERVER_RCLONE_REMOTE=b2-remote,s3-remote
GITPRESERVER_CRYPT_REMOTE=b2-crypt,s3-crypt   # b2-crypt → b2-remote, s3-crypt → s3-remote
```

If the two lists have a different number of entries, the run fails before syncing anything. With encryption on, each destination is reached through its paired crypt remote rather than the plain remote directly.
