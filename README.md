# Gentoo VirtualBox Image Builder

## Description

Unattended quick installation script for Gentoo on local VirtualBox.

## Prerequisites

- VirtualBox
- openssh, openssl, bash, curl, wget, grep, sed, coreutils
- (optional) gnupg (for livecd/admincd GPG validation)

## Usage

Run `gentoo-vbox-builder --help` for help.

Usually you just need to run script and wait until it will finish the job:

```shell
gentoo-vbox-builder
```

## Examples

![Gentoo AMD64 / Use LiveCD Kernel](/screenshots/gentoo-amd64-use-livecd-kernel.png?raw=true)

## Reporting bugs

Please use the GitHub issue tracker for any bugs or feature suggestions:

<https://github.com/sormy/gentoo-vbox-builder/issues>

## Contributing

Please submit patches to code or documentation as GitHub pull requests!

Contributions must be licensed under the MIT.

## Copyright

gentoo-vbox-builder is licensed under the MIT. A copy of this license is included in the file LICENSE.
