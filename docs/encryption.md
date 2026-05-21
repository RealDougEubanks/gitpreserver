# Encryption

GitPreserver encrypts backups at rest using **rclone crypt** — a transparent AES-256-CTR wrapper around any rclone remote. File names and directory structure are also encrypted by default, so an attacker with access to your storage bucket cannot enumerate your repository names.

Local staged backups (the `./backups/` directory) are not encrypted by GitPreserver. If you need local encryption, handle it at the filesystem or volume level.

---

## How rclone crypt works

rclone crypt is a "virtual remote" that sits in front of your actual storage backend:

```
Local backups  →  rclone crypt (encrypt)  →  B2 / S3 / Drive / etc.
```

From the backup scripts' perspective, nothing changes — they write to a path, rclone handles encryption transparently before the data reaches the remote.

**Important:** rclone crypt uses no key escrow and no recovery mechanism. If you lose your passphrase, your backup is permanently unrecoverable. Store it in Bitwarden immediately.

---

## Setup

### Step 1 — Generate a strong passphrase

```bash
openssl rand -base64 32
```

Copy the output. Store it in Bitwarden as a secure note named something like `gitpreserver rclone crypt passphrase`. Also store the salt you'll generate in Step 2.

### Step 2 — Generate a salt

The salt hardens the passphrase against brute force. rclone requires it in "obscured" form:

```bash
docker run --rm dougeubanks/gitpreserver rclone obscure 'your-strong-passphrase'
docker run --rm dougeubanks/gitpreserver rclone obscure 'your-salt-string'
```

Run both commands. The first output is `GITPRESERVER_CRYPT_PASS`, the second is `GITPRESERVER_CRYPT_PASS2`.

### Step 3 — Configure the crypt remote in rclone.conf

Add this section to `rclone/rclone.conf`, replacing the placeholders:

```ini
[gitpreserver-crypt]
type = crypt
remote = b2-remote:gitpreserver-backups
filename_encryption = standard
directory_name_encryption = true
password = RCLONE_OBSCURED_PASSPHRASE_FROM_STEP_2
password2 = RCLONE_OBSCURED_SALT_FROM_STEP_2
```

The `remote` field should point to your storage remote and bucket/path. Change `b2-remote` to match your configured backend.

### Step 4 — Enable encryption in .env

```bash
GITPRESERVER_ENCRYPT=true
GITPRESERVER_RCLONE_REMOTE=b2-remote
GITPRESERVER_CRYPT_REMOTE=gitpreserver-crypt
```

You do not need to set `GITPRESERVER_CRYPT_PASS` or `GITPRESERVER_CRYPT_PASS2` in `.env` — rclone reads them from `rclone.conf` where they are already in obscured form. If you want to override them via env vars, set them to the **original plaintext** values and rclone will obscure them at runtime.

---

## Keyfile option

For higher-security environments, you can use a keyfile instead of (or in addition to) a passphrase. Both are required for decryption when both are set.

```bash
# Generate a keyfile
openssl rand -base64 64 > /path/to/gitpreserver.key
chmod 600 /path/to/gitpreserver.key
```

Mount the keyfile into the container:

```yaml
# docker-compose.yml override
services:
  sync:
    volumes:
      - /path/to/gitpreserver.key:/run/secrets/gitpreserver.key:ro
```

Set in `.env`:

```bash
GITPRESERVER_CRYPT_KEYFILE=/run/secrets/gitpreserver.key
```

---

## Verifying encryption

After a backup run with encryption enabled, check that your storage bucket contains only encrypted, unreadable filenames:

```bash
docker run --rm \
  -v "$(pwd)/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro" \
  dougeubanks/gitpreserver \
  rclone ls b2-remote:gitpreserver-backups
```

The filenames should be random-looking strings, not recognizable repo names or paths.

To verify the crypt remote can decrypt them:

```bash
docker run --rm \
  -v "$(pwd)/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro" \
  dougeubanks/gitpreserver \
  rclone ls gitpreserver-crypt:
```

This should show the original, readable paths.

---

## Decrypting for restore

To decrypt and download a backup:

```bash
docker run --rm \
  -v "$(pwd)/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro" \
  -v /path/to/restore:/restore \
  dougeubanks/gitpreserver \
  rclone sync gitpreserver-crypt: /restore
```

See [restoring.md](restoring.md) for what to do after decrypting.

---

## Passphrase rotation (advanced)

rclone crypt does not support in-place passphrase rotation. To change your passphrase:

1. Download and decrypt the entire backup with the old passphrase
2. Configure a new crypt remote with the new passphrase
3. Re-upload the decrypted backup through the new crypt remote
4. Delete the old encrypted data from the remote

This is an expensive operation. Choose a strong passphrase upfront and store it safely — rotation is a last resort.
