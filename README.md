# Active Directory Home Lab

Windows Server 2022 domain controller + Windows 10 client running in VirtualBox. Full AD DS setup with DNS, DHCP, organizational units, users and groups, and Group Policy. All are configured manually, not scripted.

## What This Is

I built this to get hands-on with Active Directory beyond what my coursework covers. The goal was to simulate a small company network where I control identity, DNS, DHCP, and policy from a single domain controller, then prove it all works from a domain-joined client.

Everything documented here is running in my lab right now. If something's listed, I configured it and can walk through how it works.

## Lab Layout

```
┌─────────────────────────────────────────────────────┐
│                   VirtualBox Host                    │
│                                                      │
│  ┌──────────────────┐      ┌──────────────────┐     │
│  │      DC01         │      │    CLIENT01       │     │
│  │  Win Server 2022  │      │   Windows 10      │     │
│  │                   │      │   Enterprise      │     │
│  │  Roles:           │      │                   │     │
│  │  • AD DS (DC)     │      │   Domain-joined   │     │
│  │  • DNS Server     │      │   to mylab.local  │     │
│  │  • DHCP Server    │      │                   │     │
│  │                   │      │                   │     │
│  │  Internal IP:     │      │  Internal IP:     │     │
│  │  192.168.10.1     │      │  192.168.10.10    │     │
│  └────────┬─────────┘      └────────┬─────────┘     │
│           │    Internal Network (intnet)    │         │
│           └────────────────────────────────┘         │
│                    192.168.10.0/24                    │
│                                                      │
│  Both VMs also have NAT adapters for internet access │
└─────────────────────────────────────────────────────┘
```

| Component | Details |
|-----------|---------|
| Hypervisor | Oracle VirtualBox |
| Domain Controller | Windows Server 2022 Evaluation |
| Client | Windows 10 Enterprise Evaluation |
| Domain Name | `mylab.local` |
| Network | `192.168.10.0/24` (Internal Network) |
| DC IP | `192.168.10.1` |
| Client IP | `192.168.10.10` |
| DHCP Range | `192.168.10.100 – 192.168.10.200` |

## Network Setup

Each VM has two network adapters. The Internal Network adapter (`intnet`) carries all domain traffic — DNS queries, DHCP, authentication, GPO distribution. The NAT adapter just gives the VMs internet access for updates.

DC01's Internal Network adapter has a static IP of `192.168.10.1` with DNS pointing to `127.0.0.1` (itself, since it's the DNS server). The client points to `192.168.10.1` for DNS — this is the single most important setting for domain join. If the client can't find the DC via DNS, nothing works.

![DC01 network adapters — static IP and DNS on the Internal Network interface](screenshots/01-network-adapters.png)

## Active Directory

DC01 is promoted as the first (and only) domain controller in a new forest called `mylab.local`. Functional level is Windows Server 2016. DNS was installed automatically during the promotion — the forward lookup zone for `mylab.local` is AD-integrated.

Both DC01 and CLIENT01 show up as Host (A) records in the DNS zone, which confirms the client registered itself with the domain's DNS after joining.

![DNS forward lookup zone — A records for both DC01 and CLIENT01](screenshots/08-dns-forward-lookup.png)

## DHCP

DHCP is running on DC01 with a scope of `192.168.10.100–200`. The server is authorized in AD. The client actually uses a static IP (`192.168.10.10`) for lab consistency, but the scope is active — you can see CLIENT01 showing up in Address Leases.

In a real environment the client would pull an address from DHCP. I used static here so the lab is reproducible without worrying about lease changes.

![DHCP console — active scope with CLIENT01 lease](screenshots/07-dhcp-scope.png)

## OU Structure

```
mylab.local
├── IT
├── HR
├── Finance
├── Management
├── Workstations        ← CLIENT01 lives here, not in the default Computers container
├── Servers
└── Service Accounts
```

I structured OUs by department so I can target Group Policy at specific teams. Workstations, Servers, and Service Accounts are separate OUs because you don't want computer objects and service accounts mixed in with user accounts — that's a Microsoft best practice thing, and it matters once you start applying computer-level vs. user-level policies.

![OU structure in AD Users and Computers](screenshots/02-ou-structure.png)

## Users and Groups

| OU | Users | Security Group |
|----|-------|----------------|
| IT | John Doe (`jdoe`), Jane Smith (`jsmith`) | `IT-Staff` |
| HR | Sarah Miller (`smiller`), Mike Johnson (`mjohnson`) | `HR-Staff` |
| Finance | Lisa Brown (`lbrown`), Tom Wilson (`twilson`) | `Finance-Staff` |
| Management | David Clark (`dclark`) | `Management-Staff` |

Each department has a Global Security group. Every user is a member of their department's group. The groups are what I use for share permissions and GPO filtering.

![IT OU contents — users and security group](screenshots/03-users-in-ou.png)

![Jane Smith's group membership — Domain Users + IT-Staff](screenshots/04-group-membership.png)

## Group Policy

I set up three GPOs to show different levels of policy targeting:

### Password Policy — linked to `mylab.local` (applies domain-wide)

| Setting | Value | Reasoning |
|---------|-------|-----------|
| Minimum password length | 10 characters | Higher than the default 7; still usable |
| Complexity requirements | Enabled | Forces mix of uppercase, lowercase, digits, special chars |
| Maximum password age | 90 days | Standard rotation window |
| Minimum password age | 1 day | Stops users from cycling through history immediately |
| Password history | 5 passwords | Can't reuse recent passwords |
| Account lockout threshold | 5 attempts | Blocks brute-force without punishing typos too hard |
| Lockout duration | 30 minutes | Auto-unlock so helpdesk doesn't get flooded |
| Lockout counter reset | 30 minutes | Matches lockout duration |

### IT Desktop Wallpaper — linked to the IT OU only

Pushes a wallpaper image from a network share (`\\DC01\Shared\Wallpapers\company-wallpaper.jpg`). Only users in the IT OU get this — log in as an HR or Finance user and you get the default Windows wallpaper. The point is demonstrating that GPO scoping to a specific OU actually works.

### Finance Drive Mapping — linked to the Finance OU only

Maps `\\DC01\FinanceData` as the `F:` drive using Group Policy Preferences. The share permissions are locked down to the `Finance-Staff` group with Read/Change access — Everyone is removed. Log in as a Finance user and the drive appears. Log in as anyone else and it doesn't.

![Group Policy Management — GPOs linked to their respective OUs](screenshots/05-gpo-finance-drive.png)

![Password Policy settings — password and account lockout values](screenshots/06-password-policy-settings.png)

## Proof It Works

All of this was verified on CLIENT01 by logging in as different domain users and checking what policies applied.

**Domain join:**

![CLIENT01 — device name and domain confirmation](screenshots/09-domain-join-proof.png)

**Finance user sees the F: drive:**

![File Explorer as a Finance user — F: drive mapped to \\DC01\FinanceData](screenshots/10-finance-drive-map.png)

**IT user gets the wallpaper:**

![CLIENT01 desktop as an IT user — wallpaper pushed via GPO](screenshots/11-it-wallpaper.png)

**gpresult confirms which policies are hitting the client:**

This is the one that ties it all together. `gpresult /r` shows the user's OU path (`OU=IT,DC=mylab,DC=local`), which GPOs are applied (IT Desktop Wallpaper), which were filtered out, and what security groups the user belongs to. If a policy isn't applying, this is how you diagnose it.

![gpresult /r output — applied GPOs, OU path, group membership](screenshots/12-gpresult.png)

## Design Decisions

**Two adapters per VM** — Internal Network handles domain traffic, NAT handles internet. In production you'd use one network with proper routing and firewall rules. The dual-adapter thing is a lab shortcut, not an architecture choice I'd recommend.

**Static IPs on both machines** — The DC needs a static IP because it's the DNS and DHCP server. The client could use DHCP, but static makes the lab reproducible.

**`.local` domain** — Standard for isolated labs. In production, Microsoft recommends a subdomain of a domain you actually own (like `ad.company.com`) to avoid DNS conflicts with mDNS.

## What I'd Add Next

- File server with per-department NTFS permissions
- A second DC for replication and redundancy
- Group Policy for Windows Firewall rules
- LAPS for rotating local admin passwords
- Windows Server Backup for DC system state
- AD Certificate Services for internal PKI

## Reproducing This

1. Install VirtualBox
2. Grab the Windows Server 2022 and Windows 10 Enterprise evaluation ISOs from Microsoft
3. Create two VMs — 2 CPUs, 2–4GB RAM, 30–40GB disk each
4. Set up dual adapters: Adapter 1 = Internal Network (`intnet`), Adapter 2 = NAT
5. Install both OSes + VirtualBox Guest Additions
6. Follow the steps in this README

## Tools

- Oracle VirtualBox
- Windows Server 2022 (Evaluation)
- Windows 10 Enterprise (Evaluation)
- Active Directory Users and Computers
- Group Policy Management Console
- DHCP Management Console
- DNS Manager
