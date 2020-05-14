# Gentoo VirtualBox Image Builder

## Description

Unattended quick installation script for Gentoo on local VirtualBox.

## Prerequisites

- VirtualBox
- openssh, openssl, bash, curl, grep, sed, coreutils
- (optional) gnupg (for livecd/admincd GPG validation)

## Usage

Run `./gentoo-vbox-builder.sh --help` for help.

Usually you just need to run script and wait until it will finish the job:

```shell
./gentoo-vbox-builder.sh
```

Some options could be helpful to solve different problems and speedup the process:

- `--use-livecd-kernel yes` - Use precompiled kernel, modules and initramfs
  from LiveCD. The fastest way to get bootable Gentoo.
- `--use-admincd` - Workaround if minimal install cd is broken.
- `--gentoo-stage3` - Choose specific stage3 to use for bootstrap.
- `--gentoo-profile` - Choose specific profile (slow build time if used).

There are more options available, run `./gentoo-vbox-builder.sh --help` to learn more.

If specific stage3 is broken, for example, `stage3-amd64-systemd` then you still
could build using profile switch from base profile and rebuild the world, but it
will significantly increase the build time.

Please note, some profiles have no prebuilt stage3 so the only way to get them
is to use option `--gentoo-profile` but it will be most likely much slower than
if prebuilt stage3 is used.

Systemd examples:

```shell
# use precompiled stage3 with systemd - fast
./gentoo-vbox-builder.sh --gentoo-stage3 amd64-systemd
# use precompiled stage3 but rebuild with systemd support - average
./gentoo-vbox-builder.sh --gentoo-stage3 amd64 --gentoo-profile default/linux/amd64/17.0/systemd
# use precompiled stage3 but rebuild with systemd support and migrate lib32 - slow
./gentoo-vbox-builder.sh --gentoo-stage3 amd64 --gentoo-profile default/linux/amd64/17.1/systemd
```

Please note, 17.1 experimental profiles have the slowest build time
(causing gcc/glib recompilation).

Sometimes Gentoo mirrors are slightly out of sync. That could cause checksum
errors and GPG errors. In most cases it is a trancient error and process will
success after retry. By the way, you could set explicitly Gentoo mirror to use
with `--gentoo-mirror` option. List of Gentoo mirrors is available here:
<https://www.gentoo.org/downloads/mirrors/>

## Tested configurations

Not all profiles/stage3 combinations are tested. Please report an issue if
something doesn't work as expected.

Below are verified combinations that should work well.

Tested on MacBook Pro Retina 13" (Early 2013), 3.0 GHz Core i7,
2 hyper-threaded cpus (1 physical core) shared with guest. Tests below have

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 i686 --guest-name "Gentoo i686" --use-livecd-kernel yes
# Process took ~15 minutes
```

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 i686 --guest-name "Gentoo i686"
# Process took ~50 minutes
```

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 amd64 --guest-name "Gentoo amd64" --use-livecd-kernel yes
# Process took ~15 minutes
```

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 amd64 --guest-name "Gentoo amd64"
# Process took ~60 minutes
```

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 amd64-systemd --guest-name "Gentoo amd64 systemd"
# Process took ~60 minutes
```

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 amd64 --gentoo-profile default/linux/amd64/17.0/systemd  --guest-name "Gentoo amd64 17.0 systemd"
# Process took ~100 minutes
```

```shell
./gentoo-vbox-builder.sh --gentoo-stage3 amd64 --gentoo-profile default/linux/amd64/17.1/systemd  --guest-name "Gentoo amd64 17.1 systemd"
# Process took 197 minutes
```

## Troubleshooting

If you are getting error "gpg: keyserver receive failed: No route to host", then
try to use differet GPG server, for example:

```
GPG_SERVER="ipv4.pool.sks-keyservers.net" ./gentoo-vbox-builder.sh
```

## Screenshots

![Gentoo AMD64 / Use LiveCD Kernel](/screenshots/gentoo-amd64-use-livecd-kernel.png?raw=true)

## Reporting bugs

Please use the GitHub issue tracker for any bugs or feature suggestions:

<https://github.com/sormy/gentoo-vbox-builder/issues>

## Contributing

Please submit patches to code or documentation as GitHub pull requests!

Contributions must be licensed under the MIT.

## Copyright

gentoo-vbox-builder is licensed under the MIT. A copy of this license is included in the file LICENSE.
