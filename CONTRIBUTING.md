# Contributing

This repository holds the web UI of the ADS-B Exchange feeder image, the script that
installs it and the helper scripts the UI runs. Feeders install updates from it directly
over the network, so the branch layout is part of how it works.

## How a feeder updates

"Update Feeder" in the web UI runs `helpers/bg-update.sh` on the device, which fetches and
runs two scripts:

1. `update-adsbx.sh` from the `main` branch of
   [adsbx-update](https://github.com/ADSBexchange/adsbx-update) (readsb, mlat-client,
   tar1090).
2. `update-webconfig.sh` from the `master` branch of this repository. It clones `master`
   and runs `install.sh`.

Devices built from the 8.x images fetch `update-webconfig.sh` from
`dstreufert/adsbx-webconfig`, the repository this one was forked from. That script also
clones `master` of this repository and runs `install.sh`.

`install.sh` on `master` does not install the web UI itself. It selects the release branch
that matches the device, clones it and runs that branch's `install.sh`:

| `VERSION_CODENAME` (`/etc/os-release`) | `NetworkManager.service` | Branch |
|---|---|---|
| `buster`, `bullseye` | not enabled | `release/8.x` |
| `bookworm` | enabled | `release/9.x` |

Any other combination stops with a message and leaves the installed web UI unchanged. The
feed software update in step 1 is not affected.

Devices therefore always fetch `master`, and the code they end up running always comes from
a release branch.

## Branches

| Branch | Purpose |
|---|---|
| `master` | Integration. Changes merged here are not installed on devices until they are promoted to a release branch, with one exception: the selection block at the top of `install.sh` and `update-webconfig.sh` are fetched by every device on every update, so a change to either is live as soon as it is merged. Keep them small. |
| `release/9.x` | Web UI for the 9.x images (bookworm, 64-bit, NetworkManager). Promoted from `master`. |
| `release/8.x` | Web UI for the 8.0 and 8.2 images (buster and bullseye, 32-bit, wpa_supplicant and dhcpcd). A separate code base; changes are made directly on it, not merged from `master`. |

Release branches are never renamed, deleted or force-pushed. Devices depend on the names.

## Development flow

1. Branch from `master` and open a pull request against `master`.
2. Test the branch on the published images it affects. To install a checkout directly,
   bypassing the release-branch selection:

       sudo WEBCONFIG_DISPATCH=no bash install.sh dont_reset_config

3. Merge. The change is on `master` but not yet on any device.
4. Promote: fast-forward `release/9.x` to `master` and tag it.

       git checkout release/9.x && git merge --ff-only master
       git tag 9.x-$(date +%Y.%m.%d) && git push origin release/9.x --tags

   Devices install the new code the next time Update is pressed.

Changes for the 8.x images are pull requests against `release/8.x`, tested on the 8.0 and
8.2 images, and tagged `8.x-YYYY.MM.DD` when merged.

Tags record what each release branch contained on a given day; devices follow the branch
tip, not the tag.

## `WEBCONFIG_DISPATCH`

`install.sh` reads this variable. When it is `no`, the selection block is skipped and the
checkout it runs from is installed. The selection block sets it when it hands off to the
release branch, so a release branch's `install.sh` never selects again. Tests and image
builds of a specific branch set it themselves.

## Image builds

The image builder clones `master` and runs `install.sh`, so a new image receives the
release branch matching its OS. To build an image from a branch under development, run
its `install.sh` with `WEBCONFIG_DISPATCH=no`.
