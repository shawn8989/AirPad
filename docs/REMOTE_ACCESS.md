# Remote access and Files — 1.1 development candidate

Both repositories use the `codex/remote-access-files` branch. This is a coordinated
iPhone/Host update, not a public release. Existing free controls, trial duration,
Pro product, and prices are unchanged. Device acceptance is pending; the owner
will run it later. Do not mark these checks passed from a CI build.

## Setup on your iPhone and Mac mini

1. Install the matching Wield 1.1 and Wield Host 1.1 candidates. Keep a copy of the
   currently released Host so you can roll back. Use the signed installed Host,
   not a second development copy, when checking macOS permissions.
2. Install [Tailscale](https://tailscale.com/download) separately on both devices,
   sign in to the same account, and connect them. Wield does not create a VPN or
   manage your Tailscale account. [Personal pricing](https://tailscale.com/pricing)
   and [iPhone automatic connection](https://tailscale.com/docs/features/client/ios-vpn-on-demand)
   are maintained by Tailscale.
3. While both devices are on home Wi-Fi, show a new pairing QR in Wield Host.
   In Wield, open **Access away from home** and scan it. Version 2 QR codes expire
   after two minutes and can be used once. An old pairing remains usable locally,
   but one new QR scan is required for remote access and Files.
4. Select the paired Mac, copy its Tailscale name or IP into the address field,
   and tap **Save and test remote connection**. It becomes Connected only after
   the Host authenticates the phone. Keep the saved Mac for later one-tap access.
5. On the Mac, enable Accessibility and Screen Recording for the installed Host.
   Enable Launch at Login. Optionally enable **Keep available while plugged in**;
   display sleep is allowed. This cannot overcome shutdown, manual system sleep,
   a closed laptop lid, FileVault before login, or a network outage.
6. In Wield Host, choose the folders to share. In Wield's **Files** screen, open a
   folder to browse, tap a file to download/share/save to iPhone Files, or tap
   Upload and choose an individual file. Existing names receive a numbered suffix.

Remote access and Files require the existing Pro entitlement or active trial.
Local discovery uses secure pairing where available; older Hosts still support
the original local controls. New features explain that Host 1.1 and a new QR are
needed. Files can be used locally too, without Tailscale.

## Device acceptance — pending

Record the iOS/Host build, OS versions, network, result, and any screenshots/logs.
Use a temporary shared test folder with no private documents.

| Check | Expected result | Result |
|---|---|---|
| Fresh install and update from released app | Existing local pairings retained; setup and Pro reachable after onboarding | Pending |
| Cellular with Wi-Fi disabled | Saved mini connects without approval at home; Live Screen, click and typing work | Pending |
| Another Wi-Fi network | Same saved Mac connects through Tailscale | Pending |
| Switch Wi-Fi/cellular during control | Connection recovers; no false Connected state or stuck input | Pending |
| Return home | Local secure service is preferred; remote fallback works if local service fails | Pending |
| Permissions denied, then enabled | Accurate warning; no repeated permission loop; capture works after retry/relaunch as macOS requires | Pending |
| Sleep, shutdown, restart before login, Tailscale off | Connection is unavailable with recovery guidance; no false diagnosis of a permission failure | Pending |
| Keep available, display asleep | Mac mini remains reachable; disabling setting restores normal idle sleep | Pending |
| Laptop on battery (if supported hardware available) | Keep-available assertion is absent; closing lid/manual sleep are not overridden | Pending |
| Revoke phone on Host during session | Control and Files stop; reconnect requires a fresh QR | Pending |
| Download and upload text, binary, empty and large files | Original and destination hashes match; progress and completion are accurate | Pending |
| Duplicate names and concurrent same-name uploads | Every original is preserved; each completed upload gets a unique name | Pending |
| Cancel and interrupt each direction | Incomplete upload never appears as completed; explicit Retry restarts transfer | Pending |
| Change source file during download | Clear error, no completed partial file | Pending |
| Remove shared folder during transfer | Further operations fail and partial upload is removed | Pending |
| Traversal and symlinks outside shared root | Access denied; no outside reads/writes | Pending |
| Transfer while controlling/streaming | Pointer remains responsive; transfer does not queue behind video/control messages | Pending |
| Older phone/new Host and new phone/older Host | Existing local control works; unsupported new features explain required update | Pending |
| Physical keyboard/mouse after drag, pause, disconnect, app exit | No stuck buttons/modifiers or suppression | Pending |
| Pro trial/purchase/Restore and free controls | Existing entitlement behavior and pricing unchanged | Pending |

After device checks pass: upload the coordinated candidate for owner TestFlight
testing, repeat acceptance on that installed build, then prepare public release.
No new App Store submission, public Host release, or pricing changes have been
made as part of this development branch.

## Implementation and security boundaries

- Secure control uses TCP 52418 (`_wield-secure._tcp`); Files uses a separate
  connection on TCP 52419 (`_wield-files._tcp`). Tailscale carries these private
  connections. No port forwarding or Wield service is required.
- Native Network.framework TLS 1.2 PSK/AES-GCM uses independent per-pair keys.
  QR provisioning uses a random temporary key; durable keys are derived using
  HKDF-SHA256 and stored in Keychain. Control and file keys use separate contexts.
  TLS session resumption is disabled so revocation cannot reuse an old ticket.
- Application authentication verifies the saved Mac identity; the file protocol
  also proves both ends using fresh challenges. A transport-ready socket alone
  never exposes Connected controls. Old credentials cannot overwrite secure keys.
- Legacy TCP 52417/global transport key remains only for old local compatibility.
  Remote and Files never downgrade to it. This is not a redesign of the legacy
  protocol, and TLS-PSK does not provide forward secrecy.
- Host approval and Forget revoke device credentials and terminate its sessions.
  File operations recheck authorization and whether the selected root is shared.
- Shared roots use security-scoped bookmarks. Descriptor-relative openat calls
  reject path traversal, absolute paths, NULs, symlinks at every descended
  component, and nonregular files. Uploads use a hidden temporary file, fsync,
  and an atomic exclusive rename. Cancel/disconnect removes temporary uploads;
  an abrupt Host crash may leave a hidden partial file, never a completed one.
- Files are paginated, chunks are bounded to 48 KiB, each session has one active
  transfer, buffers are bounded, and idle sessions expire. Folder synchronization,
  remote deletion, editing, and transfer resumption are deliberately absent.
- Live Screen limits acknowledged clients to one pending frame, lowers JPEG
  dimensions/quality when frame round trips increase, and retains compatibility
  with older clients. ScreenCaptureKit starts asynchronously with a timeout.
  A permission error comes from capture failure, not preflight alone.

## Automated verification

No local Xcode build is used. `bash scripts/check-imports.sh` checks the iOS source;
GitHub Actions builds both apps and produces artifacts. The Host workflow tests
actual native TLS sockets with multiple credentials and rejected invalid keys,
folder boundaries, duplicate names, atomic completion/cancellation, and the
real encrypted file server/client including revocation. iOS CI exercises the
real connection manager's authentication gate, legacy acknowledgement, saved-Mac
migration, and fresh onboarding/remote setup/Pro navigation on iPhone and iPad.

These automated checks do not verify Tailscale routing, real permissions, sleep,
physical input, camera behavior, or real StoreKit transactions.
