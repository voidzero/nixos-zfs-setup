# nixos-zfs-setup.sh

## Hello, world!

This is a script that sets up new zfs storage pools on your disk(s), for use
with NixOS. It zaps the partition table(s), creates new partitions, sets up two
storage pools (named `bpool` and `rpool` by default), and prepares them for
NixOS installation.

This is a proof of concept and not for beginners. You are free to modify the
commands. The shell code shouldn't be too hard to understand.

This script is based on the instructions from the [NixOS Root on
ZFS](https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html)
website, with a few deviations and exceptions:

* It creates the partitions in a different (more sane) order;
* It names the partitions in the GPT table it creates;
* It uses `/dev/disk/by-partname` rather than `/dev/disk/by-id/*` or `/dev/disk/by-path/*`;
* It (currently) does not support disk encryption;
* It supports impermanence. Read: [Erase Your Darlings](https://grahamc.com/blog/erase-your-darlings);
* It always allocates one or more swap partitions.

## How to use this script

1.  Boot the NixOS liveCD
2.  If not using DHCP, set up networking inside the live environment.
3.  Open a terminal and login as root: `sudo login -f root`
4.  Set a password: `passwd`
5.  Restart sshd: `systemctl restart sshd.service`
6.  ssh into the shell as root: `ssh root@i.p.ad.dr`
7.  `git clone` this repository
8.  Edit the variables in `nixos-zfs-setup.sh`
9.  Optional: wipe existing partitions from the disk with `wipefs -af /dev/...`
10.  Run the script: `bash ./nixos-zfs-setup.sh` and....
11.  Hope for the best!

When the script has finished, it will tell you some commands to run next. Do
this by hand. It's best to open another shell and run those commands in there,
because the first command will output a lot of text and you might lose the
other commands. Eventually I'll get around to improve this.

## Tested with:

Qemu and vmware guests. I plan to test it on hardware when I have a chance to.
This may take a long time because I have plenty of other NixOS related stuff to
figure out first.

## Todo

* Add encryption.

## Feedback

Feedback is thankfully welcomed on the github issue tracker.

## Blurb

<sup><sub>Copyright © Mark van Dijk, 2022, The Netherlands.  This product is
licensed under the GPLv3. It comes with ABSOLUTELY NO WARRANTY.  This is free
software, and you are welcome to redistribute it under certain conditions; see
the LICENSE file for more information.</sub></sup>

