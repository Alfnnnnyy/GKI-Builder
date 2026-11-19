# Kernel Changelog

- [F6] Enable `CONFIG_HZ_300=y` (align scheduler tick with 60/120Hz display refresh)
- [Net] Enable `CONFIG_NET_SCH_DEFAULT=y` & `CONFIG_DEFAULT_FQ=y` (default qdisc=fq for TCP BBR)
- [SELinux] Hide KernelSU/Magisk context queries & DirtySepolicy checks
- [NoMount] Integrated NoMount VFS driver v2.3.0
