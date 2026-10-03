# ParishBSD

## Overview

ParishBSD is an operating system based on FreeBSD that was heavily inspired by QubesOS.

ParishBSD allows creating isolated compartments (or containers; functionally it's freebsd-jails). If one of the compartments got compromised then the rest of the system is still safe. Interestingly, if the host system has been compromised then the containers are still safe (unless root access was acquired).
An user can create vault that has no network connection to securely store information.

**Primarily, ParishBSD was made for Churches and Parishes to provide maximum security and easy use.** This goal was proposed due to the **tendency** and **current movements** of the large IT companies trying to **integrate AI agents' full control** within the operating system.

Where it's not the user who controls the computer. It will be an AI agent. User instead would give commands to the AI agent and it will do whatever it will do. This **results in revoking the 100% freedom of the user** over his computer and his confidential data.

Operating system itself implies giving easy access and interface to the user to execute commands on the computer as said user needs. It's been like that for centuries. But integration of the movement described above implies that it would be not operating system at all. It's just a machine running itself through fancy layer of OS and firmware. This poses all the users at risk, especcially church workers.

Therefore, ParishBSD was proposed as an easy to use and secure alternative for users (for both those who don't have extensive experience in computers and those who do) to securely and freely use computer.

A 2026 analysis of digitalization in church administration concludes that electronic procedures are permissible only if they ensure the same legal safeguards as paper: clear attribution, authenticity, integrity of documents, proof of notification, controlled access, and appropriate technical safeguards. ParishBSD fulfills all of these safeguards.

ParishBSD includes:
- Secure storage of financial data
- Secure storage of counseling notes (spiritual guidance) that needs to be remained private
- ChurchCRM - to store church management data

Additionally, it's possible to host your parish/church website using this OS.

Although, as explained above ParishBSD does use fully isolated containers it does not require a lot of hardware resources. In fact, ParishBSD can be considered lightweight.

For more information on how exactly the security is managed please read the section below.

## Technologically

### Containers (App containers, Vault containers, ...)

ParishBSD provides template containers which have their own predefined configurations for easier and fast setup of containers.

1. **App containers** are considered "thick" jails (freebsd-jails ZFS-clone of template with base system) and **they're allocated on different ZFS dataset** within the filesystem providing **isolation from the host system**. Whether or not the container has access to outside network depends on the configuration.

2. **Vault containers** are considered "thick" jails (freebsd-jails ZFS-clone of template with base system) and **they're allocated on different ZFS dataset** with `encryption=on` within the filesystem providing **isolation with encryption from the host system**.
    - Vault containers have NO outside network access.
    - All the data within the vault containers is encrypted. Even if the host system was compromised (attacker escaped from app container to the host) then it's still impossible to view the contents of the vault.
    - Secrets for encryption live in additional data dataset.
    - **This is WAY safer approach to secure sensetive data** than any OS such as Windows, MacOS and GNU/Linux (functionally it's not possible to provide same isolation within Linux kernel).

Management of said containers can be done through additional isolated container which has no outside network access.

ChurchCRM application that comes with the system is also used in another isolated container with no outside network access to securely and locally store data.

### Display manager and desktop manager

ParishBSD uses Xpra to connect socket from container to the host for display running applications.

