# Dev Diary — Continuous File Sync Setup (2025-08-12)

- Set up continuous sync between local and remote (SiteGround) WordPress files using `fswatch` + `rsync`.
- Installed `fswatch` via Homebrew for real-time file change monitoring on macOS.
- Created a watcher script that triggers `rsync` to upload local changes immediately to the remote SiteGround server via SSH alias `miguelbarroso`.
- Benefits:  
  - Near real-time sync without heavy polling  
  - No GUI needed, fully CLI-based  
  - Reliable for quick iterative development and deployment

## Usage command example

```bash
#!/bin/bash
fswatch -o "/Users/mb/QNAP/Businesses/Miguel Barroso/public_html/" | while read; do
  rsync -avz --delete -e ssh "/Users/mb/QNAP/Businesses/Miguel Barroso/public_html/" miguelbarroso:/home/<your-siteground-account>/www/miguelbarroso.com/public_html/
done
```

## Next steps
- Add exclusion rules for cache/temp files to optimize sync speed.

### Fixed 403 Forbidden caused by wrong folder permissions after rsync sync

- Found that rsync script was syncing with `700` permissions on folders.
- Web server was denied access due to restrictive permissions.
- Corrected permissions on server with `find` commands to set folders to `755` and files to `644`.
- Updated rsync command to include `--chmod` option to enforce correct permissions on sync.

```bash
rsync -avz --delete --no-perms -e ssh "/Users/mb/QNAP/Businesses/Miguel Barroso/public_html/" miguelbarroso:/home/<your-siteground-account>/www/miguelbarroso.com/public_html/
```

## Explanation
-	--no-perms means don’t preserve file permissions from the source, so remote files and folders will get created with the remote system’s default permissions.
-	This avoids permission messes caused by syncing permissions back and forth.

This ensures the webserver can read and enter the directories and read the files properly.

## Use this command

```bash
#!/bin/bash
fswatch -o "/Users/mb/QNAP/Businesses/Miguel Barroso/public_html/" | while read; do
  rsync -avz --delete --no-perms -e ssh "/Users/mb/QNAP/Businesses/Miguel Barroso/public_html/" miguelbarroso:/home/<your-siteground-account>/www/miguelbarroso.com/public_html/
done
```

# Abandoning this approach
Reason is that this sync is not 2-way and there is risk of collisions when sometimes editing locally, sometimes editing from WordPress UI. Also, many changes are in the database which is not reflected in either. It was an educational run however.