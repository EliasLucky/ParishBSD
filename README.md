# ParishBSD
ParishBSD based on FreeBSD and inspired by QubesOS. Allows creating isolated "compartments" (freebsd-jails). If one of the compartments got compromised then the rest of the system is still safe. For example, create vault that has no network connection to securely store information. Uses Xpra (to connect socket from jail to host) to display apps.
