#!/usr/bin/env bash
#
# security-audit.sh — Read-only security posture audit for internet-exposed
# Linux VMs / NAS boxes (Ubuntu/Debian, RHEL/CentOS/Fedora, TrueNAS SCALE,
# Synology DSM, etc). Produces a single Markdown report you can hand to a
# human or paste into any AI agent to get concrete remediation steps.
#
# WHAT IT DOES:
#   - Only reads system state (config files, process/socket tables, logs).
#   - Never installs, changes, restarts, or deletes anything.
#   - Skips any check whose required tool is missing, and says so.
#
# USAGE:
#   sudo ./security-audit.sh [-o OUTPUT_DIR] [--no-color] [-h]
#
# Run with sudo/root for a complete audit — several checks (shadow file,
# full SUID scan, per-user cron, process owners) are skipped without it.
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_VERSION="1.0"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
HOSTNAME_STR="$(hostname 2>/dev/null || echo unknown-host)"
OUT_DIR="$HOME/security-audit-reports"
USE_COLOR=true
[[ -t 1 ]] || USE_COLOR=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-dir) OUT_DIR="$2"; shift 2 ;;
    --no-color) USE_COLOR=false; shift ;;
    -h|--help)
      grep '^#' "$0" | sed -e 's/^#//' -e 's/^!\/usr.*//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR" 2>/dev/null || { echo "Cannot create output dir $OUT_DIR" >&2; exit 1; }
REPORT_MD="${OUT_DIR}/security-audit-${HOSTNAME_STR}-${TIMESTAMP}.md"
FINDINGS_TMP="$(mktemp)"
trap 'rm -f "$FINDINGS_TMP"' EXIT

IS_ROOT=false
[[ "${EUID:-$(id -u)}" -eq 0 ]] && IS_ROOT=true

declare -A SEV_COUNT=( [CRITICAL]=0 [HIGH]=0 [MEDIUM]=0 [LOW]=0 [INFO]=0 [PASS]=0 )

if $USE_COLOR; then
  C_RESET='\033[0m'; C_CRIT='\033[1;41;97m'; C_HIGH='\033[1;31m'
  C_MED='\033[1;33m'; C_LOW='\033[36m'; C_INFO='\033[90m'; C_PASS='\033[32m'
  C_HDR='\033[1;34m'
else
  C_RESET=''; C_CRIT=''; C_HIGH=''; C_MED=''; C_LOW=''; C_INFO=''; C_PASS=''; C_HDR=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

progress() { echo -e "${C_HDR}[*]${C_RESET} $1" >&2; }

sev_color() {
  case "$1" in
    CRITICAL) echo -n "$C_CRIT" ;;
    HIGH) echo -n "$C_HIGH" ;;
    MEDIUM) echo -n "$C_MED" ;;
    LOW) echo -n "$C_LOW" ;;
    INFO) echo -n "$C_INFO" ;;
    PASS) echo -n "$C_PASS" ;;
  esac
}

# add_finding SEVERITY "Title" "Explanation" ["evidence text"]
add_finding() {
  local sev="$1" title="$2" detail="$3" evidence="${4:-}"
  SEV_COUNT[$sev]=$(( ${SEV_COUNT[$sev]} + 1 ))
  echo -e "$(sev_color "$sev")[$sev]${C_RESET} $title" >&2
  {
    echo "### [$sev] $title"
    echo
    [[ -n "$detail" ]] && echo "$detail"
    if [[ -n "$evidence" ]]; then
      echo
      echo '```'
      echo "$evidence"
      echo '```'
    fi
    echo
  } >> "$FINDINGS_TMP"
}

section() {
  progress "== $1 =="
  { echo; echo "## $1"; echo; } >> "$FINDINGS_TMP"
}

not_available() {
  # note a skipped check without counting it as a finding
  { echo "_Skipped: $1._"; echo; } >> "$FINDINGS_TMP"
}

truncate_output() {
  local max="$1" total input
  input="$(cat)"
  [[ -z "$input" ]] && return
  total=$(printf '%s\n' "$input" | wc -l)
  if (( total > max )); then
    printf '%s\n' "$input" | head -n "$max"
    echo "... (truncated, $((total - max)) more lines not shown)"
  else
    printf '%s\n' "$input"
  fi
}

run_timeout() {
  # run_timeout SECONDS cmd...
  local secs="$1"; shift
  if has_cmd timeout; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

classify_addr() {
  local addr="$1"
  case "$addr" in
    127.0.0.1|::1) echo "localhost" ;;
    0.0.0.0|::|'*') echo "all-interfaces" ;;
    10.*|192.168.*) echo "private" ;;
    172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) echo "private" ;;
    169.254.*) echo "link-local" ;;
    *) echo "public-or-other" ;;
  esac
}

parse_addr_port() {
  # prints "ADDR PORT" for input like 0.0.0.0:22 or [::]:22
  local ap="$1" addr port
  if [[ "$ap" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
    addr="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"
  elif [[ "$ap" == *:* ]]; then
    addr="${ap%:*}"; port="${ap##*:}"
  else
    addr="$ap"; port=""
  fi
  echo "$addr $port"
}

# ---------------------------------------------------------------------------
# Report header (filled at the very end once counts are known)
# ---------------------------------------------------------------------------
write_header() {
  local risk="No major issues found — keep monitoring and re-run periodically."
  if (( SEV_COUNT[CRITICAL] > 0 )); then
    risk="URGENT: one or more CRITICAL issues found. Treat as a priority."
  elif (( SEV_COUNT[HIGH] > 0 )); then
    risk="ACTION RECOMMENDED SOON: HIGH severity issues found."
  elif (( SEV_COUNT[MEDIUM] > 0 )); then
    risk="Review recommended: MEDIUM severity issues found."
  fi

  cat <<EOF
# Security Audit Report

- **Host:** ${HOSTNAME_STR}
- **Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')
- **Ran as root:** ${IS_ROOT}
- **Script version:** ${SCRIPT_VERSION}

## Overall assessment

**${risk}**

| Severity | Count |
|---|---|
| CRITICAL | ${SEV_COUNT[CRITICAL]} |
| HIGH     | ${SEV_COUNT[HIGH]} |
| MEDIUM   | ${SEV_COUNT[MEDIUM]} |
| LOW      | ${SEV_COUNT[LOW]} |
| INFO     | ${SEV_COUNT[INFO]} |
| PASS     | ${SEV_COUNT[PASS]} |

## Severity key

- **CRITICAL** — actively and trivially exploitable from the internet (e.g. an
  unauthenticated database or admin API bound to a public interface). Fix now.
- **HIGH** — a real, well-known attack vector (weak SSH config, exposed file
  share, no firewall). Fix soon.
- **MEDIUM** — weakens your defenses or increases blast radius but isn't
  directly exploitable on its own.
- **LOW** — best-practice / hardening suggestion.
- **INFO** — context for whoever reads this report; no action implied.
- **PASS** — checked and looks fine.

## How to use this report

This was generated by a read-only audit script — nothing here was changed on
the system. Paste this whole document into an AI coding/security assistant
(Claude, etc.) and ask something like:

> "Here is a security audit of my server. Give me the exact commands to fix
> every CRITICAL and HIGH finding, in priority order, and flag anything that
> needs me to confirm before you'd apply it (e.g. changing SSH port, firewall
> rules that could lock me out)."

**Caveat on "exposed to internet":** this script sees what's listening on the
box itself. Whether a given port is *actually* reachable from the internet
also depends on your router / NAT / cloud security group rules — cross-check
findings marked "all interfaces" or "public IP" against those.

---

EOF
}

# ===========================================================================
# CHECKS
# ===========================================================================

check_system_info() {
  section "System Information"
  local os kernel uptime_s virt
  os="$( { [[ -r /etc/os-release ]] && . /etc/os-release && echo "$PRETTY_NAME"; } 2>/dev/null || uname -s)"
  kernel="$(uname -r 2>/dev/null || echo unknown)"
  uptime_s="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
  virt="unknown"
  has_cmd systemd-detect-virt && virt="$(systemd-detect-virt 2>/dev/null || echo none)"

  add_finding "INFO" "System summary" \
    "OS, kernel, uptime and virtualization context for this report." \
    "$(printf 'OS: %s\nKernel: %s\nUptime: %s\nVirtualization: %s\n' "$os" "$kernel" "$uptime_s" "$virt")"

  if ! $IS_ROOT; then
    add_finding "INFO" "Not running as root" \
      "Several checks (shadow file audit, password aging, full SUID scan, per-process owners, some cron files) need root to be complete. Re-run with 'sudo' for full coverage." ""
  fi
}

check_updates() {
  section "Pending OS Updates"
  if has_cmd apt; then
    local upgradable
    upgradable="$(apt list --upgradable 2>/dev/null | grep -v '^Listing' || true)"
    local sec_count total_count
    total_count="$(printf '%s\n' "$upgradable" | grep -c . || true)"
    sec_count="$(printf '%s\n' "$upgradable" | grep -ic security || true)"
    if [[ "$total_count" -gt 0 ]]; then
      local sev="MEDIUM"; [[ "$sec_count" -gt 0 ]] && sev="HIGH"
      add_finding "$sev" "Pending package updates ($total_count, $sec_count security)" \
        "Unpatched packages are one of the most common ways internet-facing hosts get compromised. Review and apply updates (apt-get upgrade), prioritizing anything tagged security." \
        "$(printf '%s\n' "$upgradable" | truncate_output 25)"
    else
      add_finding "PASS" "OS packages up to date (apt)" "No pending upgrades found in the local apt cache. Note: run 'apt update' first if this hasn't been refreshed recently." ""
    fi
    [[ -f /var/run/reboot-required ]] && add_finding "MEDIUM" "Reboot required" "A previous update (likely kernel) needs a reboot to take effect. Until then the running kernel may still have known vulnerabilities patched on disk but not active." "$(cat /var/run/reboot-required 2>/dev/null)"
  elif has_cmd dnf; then
    local out
    out="$(dnf -q check-update 2>/dev/null)"; local rc=$?
    if [[ $rc -eq 100 ]]; then
      add_finding "MEDIUM" "Pending package updates (dnf)" "Unpatched packages found. Run 'dnf check-update' then 'dnf upgrade'." "$(printf '%s\n' "$out" | truncate_output 25)"
    else
      add_finding "PASS" "OS packages up to date (dnf)" "No pending updates reported by dnf." ""
    fi
  elif has_cmd yum; then
    local out
    out="$(yum -q check-update 2>/dev/null)"; local rc=$?
    if [[ $rc -eq 100 ]]; then
      add_finding "MEDIUM" "Pending package updates (yum)" "Unpatched packages found. Run 'yum check-update' then 'yum update'." "$(printf '%s\n' "$out" | truncate_output 25)"
    else
      add_finding "PASS" "OS packages up to date (yum)" "No pending updates reported by yum." ""
    fi
  else
    not_available "no supported package manager found (apt/dnf/yum)"
  fi

  # Auto-update mechanism
  if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && grep -q '"1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
    add_finding "PASS" "Unattended security upgrades enabled" "System is configured to automatically install updates." ""
  elif has_cmd dnf && systemctl is-enabled dnf-automatic.timer >/dev/null 2>&1; then
    add_finding "PASS" "dnf-automatic enabled" "System is configured to automatically check/install updates." ""
  else
    add_finding "LOW" "No automatic security updates detected" "Consider enabling unattended-upgrades (Debian/Ubuntu) or dnf-automatic (RHEL/Fedora) so security patches land without manual intervention." ""
  fi
}

check_network_exposure() {
  section "Listening Services / Network Exposure"

  declare -A RISKY_DESC=(
    [21]="FTP — often cleartext auth" [23]="Telnet — cleartext remote shell"
    [111]="rpcbind" [139]="SMB (NetBIOS)" [445]="SMB"
    [512]="rexec" [513]="rlogin" [514]="rsh"
    [1433]="MSSQL" [2049]="NFS" [2375]="Docker API (no TLS)"
    [3306]="MySQL/MariaDB" [3389]="RDP" [5432]="PostgreSQL"
    [5900]="VNC" [5901]="VNC" [5902]="VNC"
    [6379]="Redis" [9200]="Elasticsearch" [9300]="Elasticsearch (transport)"
    [11211]="Memcached" [27017]="MongoDB" [548]="AFP"
  )
  declare -A RISKY_SEV=(
    [21]="HIGH" [23]="CRITICAL" [111]="MEDIUM" [139]="HIGH" [445]="HIGH"
    [512]="CRITICAL" [513]="CRITICAL" [514]="CRITICAL" [1433]="HIGH"
    [2049]="HIGH" [2375]="CRITICAL" [3306]="HIGH" [3389]="HIGH"
    [5432]="HIGH" [5900]="HIGH" [5901]="HIGH" [5902]="HIGH"
    [6379]="CRITICAL" [9200]="CRITICAL" [9300]="CRITICAL" [11211]="CRITICAL"
    [27017]="CRITICAL" [548]="MEDIUM"
  )

  local ss_out=""
  if has_cmd ss; then
    ss_out="$(ss -tulnH 2>/dev/null)"
  elif has_cmd netstat; then
    ss_out="$(netstat -tulnH 2>/dev/null || netstat -tuln 2>/dev/null | tail -n +3)"
  fi

  if [[ -z "$ss_out" ]]; then
    not_available "ss and netstat are both unavailable, so listening sockets could not be enumerated"
  else
    local all_summary="" flagged_any=false
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local local_field
      local_field="$(awk '{print $5}' <<<"$line")"
      [[ -z "$local_field" ]] && continue
      read -r addr port <<<"$(parse_addr_port "$local_field")"
      [[ -z "$port" ]] && continue
      local cls; cls="$(classify_addr "$addr")"
      all_summary+="$(printf '%-8s %-15s port %-6s [%s]\n' "$(awk '{print $1}' <<<"$line")" "$addr" "$port" "$cls")"
      if [[ "$cls" == "all-interfaces" || "$cls" == "public-or-other" ]]; then
        if [[ -n "${RISKY_DESC[$port]:-}" ]]; then
          flagged_any=true
          add_finding "${RISKY_SEV[$port]}" "Port $port (${RISKY_DESC[$port]}) reachable on all interfaces" \
            "This service is bound to $addr, meaning it listens on every network interface (not just localhost). If your firewall/router/cloud security group doesn't block it, it is reachable from the internet. ${RISKY_DESC[$port]} attacks (credential stuffing, known unauthenticated-by-default access, or cleartext credential capture) are commonly automated by internet-wide scanners." \
            "$line"
        fi
      fi
    done <<<"$ss_out"

    add_finding "INFO" "All listening sockets" \
      "Full list of listening TCP/UDP sockets and how their bind address was classified. 'all-interfaces' = listens on every NIC (exposure depends on your firewall/router). 'public-or-other' = bound directly to a specific address that isn't private/localhost — check it. 'private' = LAN only, unless port-forwarded. 'localhost' = not network-reachable at all." \
      "$(printf '%s' "$all_summary" | sort -u | truncate_output 40)"

    $flagged_any || add_finding "PASS" "No commonly-exploited ports found bound to all interfaces" "Checked against a list of high-risk services (databases, Telnet, RDP, VNC, SMB, NFS, Docker API, etc.)." ""
  fi

  # Public IP (best-effort, network required)
  if has_cmd curl; then
    local pub_ip
    pub_ip="$(run_timeout 3 curl -s https://ifconfig.me 2>/dev/null || true)"
    if [[ "$pub_ip" =~ ^[0-9a-fA-F:.]{3,45}$ ]]; then
      add_finding "INFO" "Public IP address" "For cross-referencing with an external port scan (e.g. from another network, or a service like shodan.io / nmap from outside)." "$pub_ip"
    else
      add_finding "INFO" "Could not determine public IP" "No outbound internet access from this host, the lookup timed out, or it was intercepted by a proxy. Not necessarily a problem." ""
    fi
  fi
}

check_firewall() {
  section "Host Firewall"
  local found=false
  if has_cmd ufw; then
    found=true
    local st; st="$(ufw status verbose 2>/dev/null || true)"
    if grep -qi "Status: active" <<<"$st"; then
      add_finding "PASS" "UFW firewall is active" "" "$(truncate_output 20 <<<"$st")"
    else
      add_finding "HIGH" "UFW is installed but inactive" "A host firewall is present but not enabled, so there's no local filtering — every listening port is reachable subject only to upstream network rules. Enable with 'ufw enable' after confirming your SSH rule is allowed." "$(truncate_output 10 <<<"$st")"
    fi
  fi
  if has_cmd firewall-cmd; then
    found=true
    if systemctl is-active firewalld >/dev/null 2>&1; then
      add_finding "PASS" "firewalld is active" "" "$(firewall-cmd --state 2>/dev/null; firewall-cmd --list-all 2>/dev/null | truncate_output 20)"
    else
      add_finding "HIGH" "firewalld installed but not running" "Enable with 'systemctl enable --now firewalld' after checking allowed services/ports." ""
    fi
  fi
  if has_cmd nft; then
    local rules; rules="$(nft list ruleset 2>/dev/null || true)"
    if [[ -n "$rules" ]]; then
      found=true
      add_finding "INFO" "nftables ruleset present" "Raw nftables rules found (may be managed by ufw/firewalld already listed above, or standalone)." "$(truncate_output 25 <<<"$rules")"
    fi
  fi
  if ! $found && has_cmd iptables; then
    local rules; rules="$(iptables -L -n 2>/dev/null || true)"
    if grep -q "Chain INPUT (policy ACCEPT)" <<<"$rules" && [[ "$(wc -l <<<"$rules")" -le 8 ]]; then
      found=true
      add_finding "HIGH" "iptables has no meaningful filtering" "INPUT chain policy is ACCEPT with no rules — effectively no firewall. Every listening service is exposed subject only to upstream network controls." "$(truncate_output 15 <<<"$rules")"
    elif [[ -n "$rules" ]]; then
      found=true
      add_finding "INFO" "iptables rules present" "Raw iptables ruleset (not managed by ufw/firewalld)." "$(truncate_output 25 <<<"$rules")"
    fi
  fi
  $found || not_available "no host firewall tool found (ufw, firewalld, nft, iptables all absent)"
}

check_ssh() {
  section "SSH Hardening"
  local cfg="/etc/ssh/sshd_config"
  if [[ ! -r "$cfg" ]]; then
    not_available "/etc/ssh/sshd_config not present or not readable (SSH may not be installed, or re-run as root)"
    return
  fi

  # sshd_config can also live in /etc/ssh/sshd_config.d/*.conf on newer distros — fold those in.
  local effective
  effective="$(cat "$cfg" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | grep -Ev '^\s*#|^\s*$')"

  get_directive() {
    # returns the LAST matching value (sshd uses first-match-wins in the file,
    # but for a simple audit we just want to know if it's set at all / to what)
    grep -iE "^\s*$1\s+" <<<"$effective" | tail -1 | awk '{print $2}'
  }

  local port perm_root pass_auth empty_pw pubkey_auth max_tries x11
  port="$(get_directive Port)"; port="${port:-22}"
  perm_root="$(get_directive PermitRootLogin)"; perm_root="${perm_root:-prohibit-password}"
  pass_auth="$(get_directive PasswordAuthentication)"; pass_auth="${pass_auth:-yes}"
  empty_pw="$(get_directive PermitEmptyPasswords)"; empty_pw="${empty_pw:-no}"
  pubkey_auth="$(get_directive PubkeyAuthentication)"; pubkey_auth="${pubkey_auth:-yes}"
  max_tries="$(get_directive MaxAuthTries)"; max_tries="${max_tries:-6}"
  x11="$(get_directive X11Forwarding)"; x11="${x11:-no}"

  case "$perm_root" in
    yes) add_finding "CRITICAL" "SSH root login permitted (PermitRootLogin yes)" "Root can log in directly over SSH. Combined with password auth this is one of the most common ways servers get taken over. Set 'PermitRootLogin no' and use sudo from a normal account instead." "PermitRootLogin $perm_root" ;;
    prohibit-password|without-password) add_finding "PASS" "Root SSH login restricted to keys only" "" "PermitRootLogin $perm_root" ;;
    no) add_finding "PASS" "Root SSH login disabled" "" "PermitRootLogin $perm_root" ;;
  esac

  if [[ "$pass_auth" == "yes" ]]; then
    add_finding "HIGH" "SSH password authentication is enabled" "Password auth over SSH is directly brute-forceable from the internet by automated botnets. Switch to key-based auth and set 'PasswordAuthentication no'." "PasswordAuthentication $pass_auth"
  else
    add_finding "PASS" "SSH password authentication disabled" "Key-based auth only." "PasswordAuthentication $pass_auth"
  fi

  if [[ "$empty_pw" == "yes" ]]; then
    add_finding "CRITICAL" "SSH permits empty passwords" "Set 'PermitEmptyPasswords no' immediately." "PermitEmptyPasswords $empty_pw"
  fi

  if [[ "$port" == "22" ]]; then
    add_finding "LOW" "SSH on default port 22" "Not a real security boundary, but moving off 22 cuts down noise from opportunistic scanners considerably. Optional, low priority compared to the auth-method findings above." "Port $port"
  fi

  if [[ "$max_tries" -gt 6 ]] 2>/dev/null; then
    add_finding "LOW" "MaxAuthTries is high ($max_tries)" "Lower to make online brute-forcing slower (e.g. 3-4)." "MaxAuthTries $max_tries"
  fi

  [[ "$x11" == "yes" ]] && add_finding "LOW" "X11Forwarding enabled" "Rarely needed on a server; disable unless you specifically use it." "X11Forwarding $x11"

  # authorized_keys permissions, briefly
  local homes=(/root /home/*)
  local bad_perms=""
  for h in "${homes[@]}"; do
    local ak="$h/.ssh/authorized_keys"
    if [[ -f "$ak" ]]; then
      local perm; perm="$(stat -c '%a' "$ak" 2>/dev/null || stat -f '%Lp' "$ak" 2>/dev/null)"
      [[ "$perm" != "600" && "$perm" != "400" ]] && bad_perms+="$ak: $perm\n"
    fi
  done
  if [[ -n "$bad_perms" ]]; then
    add_finding "MEDIUM" "authorized_keys with loose permissions" "Should be 600 (owner read/write only). chmod 600 the files listed." "$(echo -e "$bad_perms")"
  fi
}

check_fail2ban() {
  section "Brute-force Protection"
  if has_cmd fail2ban-client; then
    if systemctl is-active fail2ban >/dev/null 2>&1 || pgrep -x fail2ban-server >/dev/null 2>&1; then
      add_finding "PASS" "fail2ban is running" "$(fail2ban-client status 2>/dev/null | truncate_output 10)"
    else
      add_finding "MEDIUM" "fail2ban installed but not running" "Start it: 'systemctl enable --now fail2ban'." ""
    fi
  elif has_cmd sshguard; then
    add_finding "PASS" "sshguard present" "" ""
  else
    add_finding "MEDIUM" "No brute-force protection tool detected" "Nothing like fail2ban/sshguard found. If any service accepting passwords is internet-facing, install fail2ban to auto-block repeated failed logins." ""
  fi
}

check_users() {
  section "User & Authentication Audit"

  # UID 0 accounts other than root
  local dup_root
  dup_root="$(awk -F: '($3==0 && $1!="root"){print $1}' /etc/passwd 2>/dev/null)"
  if [[ -n "$dup_root" ]]; then
    add_finding "CRITICAL" "Non-root account(s) with UID 0" "Any account with UID 0 has full root privileges regardless of its name. This is either a serious misconfiguration or a sign of compromise." "$dup_root"
  else
    add_finding "PASS" "No unexpected UID 0 accounts" "" ""
  fi

  if $IS_ROOT && [[ -r /etc/shadow ]]; then
    local empty_pw
    empty_pw="$(awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null)"
    if [[ -n "$empty_pw" ]]; then
      add_finding "CRITICAL" "Account(s) with empty password" "Anyone can log in as these users with no password at all (if PAM allows it). Lock or set a password immediately: 'passwd -l <user>'." "$empty_pw"
    else
      add_finding "PASS" "No accounts with empty passwords" "" ""
    fi

  else
    not_available "/etc/shadow not readable (need root for empty-password checks)"
  fi

  if [[ -r /etc/login.defs ]]; then
    local pass_max
    pass_max="$(awk '/^\s*PASS_MAX_DAYS/{print $2}' /etc/login.defs 2>/dev/null | head -1)"
    if [[ -z "$pass_max" ]] || (( pass_max > 365 )) 2>/dev/null; then
      add_finding "LOW" "No effective password-expiration policy (PASS_MAX_DAYS)" "System default allows passwords to never meaningfully expire. Only matters where password auth is actually used (SSH password auth, local console, service accounts) — low priority if you rely on SSH keys / MFA everywhere." "PASS_MAX_DAYS: ${pass_max:-unset}"
    fi
  fi

  # sudoers NOPASSWD
  local nopass=""
  [[ -r /etc/sudoers ]] && nopass+="$(grep -RhE '^\s*[^#].*NOPASSWD' /etc/sudoers 2>/dev/null)"
  [[ -d /etc/sudoers.d ]] && nopass+=$'\n'"$(grep -RhE '^\s*[^#].*NOPASSWD' /etc/sudoers.d/ 2>/dev/null)"
  nopass="$(echo "$nopass" | grep -v '^\s*$' || true)"
  if [[ -n "$nopass" ]]; then
    add_finding "MEDIUM" "sudo NOPASSWD rules present" "These accounts/commands can escalate to root without a password prompt. Confirm each entry is intentional and as narrowly scoped as possible." "$nopass"
  fi

  # who has sudo/wheel group membership
  local sudo_group_members
  sudo_group_members="$(getent group sudo wheel 2>/dev/null | awk -F: '{print $1": "$4}')"
  [[ -n "$sudo_group_members" ]] && add_finding "INFO" "Members of sudo/wheel groups" "" "$sudo_group_members"
}

check_auth_failures() {
  section "Recent Failed Login Attempts"
  local log=""
  for f in /var/log/auth.log /var/log/secure; do
    [[ -r "$f" ]] && log="$f" && break
  done
  if [[ -z "$log" ]] && has_cmd journalctl; then
    local jout
    jout="$(run_timeout 5 journalctl -u sshd -q --no-pager 2>/dev/null | grep -i "Failed password" | tail -500)"
    if [[ -n "$jout" ]]; then
      local count top
      count="$(wc -l <<<"$jout")"
      top="$(grep -oE 'from [0-9a-fA-F:.]+' <<<"$jout" | awk '{print $2}' | sort | uniq -c | sort -rn | head -10)"
      add_finding "INFO" "SSH failed login attempts (journal, recent)" "$count failed attempts found in recent journal entries. Top source IPs below — if any single IP dominates, consider blocking it and confirm fail2ban (see above) is active." "$top"
    else
      add_finding "PASS" "No recent SSH failed-login entries found in journal" "" ""
    fi
    return
  fi
  if [[ -z "$log" ]]; then
    not_available "no auth.log, secure log, or journalctl found — could not check failed login history"
    return
  fi
  local count top
  count="$(grep -c "Failed password" "$log" 2>/dev/null || echo 0)"
  if [[ "$count" -gt 0 ]]; then
    top="$(grep "Failed password" "$log" 2>/dev/null | grep -oE 'from [0-9a-fA-F:.]+' | awk '{print $2}' | sort | uniq -c | sort -rn | head -10)"
    local sev="INFO"; [[ "$count" -gt 200 ]] && sev="MEDIUM"
    add_finding "$sev" "SSH failed login attempts: $count" "This host is being actively scanned/brute-forced from these top source IPs. If fail2ban isn't already blocking them, that's the fix — see Brute-force Protection section above." "$top"
  else
    add_finding "PASS" "No SSH failed-login attempts found in $log" "" ""
  fi
}

check_file_perms() {
  section "Sensitive File Permissions"
  for f in /etc/passwd /etc/shadow /etc/ssh/sshd_config; do
    [[ -e "$f" ]] || continue
    local perm; perm="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)"
    case "$f" in
      */shadow)
        if [[ "$perm" != "000" && "$perm" != "600" && "$perm" != "640" ]]; then
          add_finding "HIGH" "$f has loose permissions ($perm)" "This file holds password hashes. It should not be world-readable. Expected 600 or 640." "$f: $perm"
        fi ;;
      *)
        [[ "${perm:0-1}" -gt 4 ]] 2>/dev/null && add_finding "LOW" "$f is world-writable" "Unexpected — verify nothing else on the box can tamper with it." "$f: $perm"
        ;;
    esac
  done

  if $IS_ROOT || [[ -O /etc ]]; then
    progress "Scanning common system directories for world-writable files (this can take a moment)..."
    local ww
    ww="$(run_timeout 45 find /etc /usr /opt /root /var/www /var/spool/cron -xdev -type f -perm -0002 2>/dev/null)"
    if [[ -n "$ww" ]]; then
      add_finding "MEDIUM" "World-writable files in system directories" "Any local user (or compromised low-priv process) can modify these. Review and tighten permissions (chmod o-w)." "$(truncate_output 25 <<<"$ww")"
    else
      add_finding "PASS" "No world-writable files found in scanned system directories" "Scanned: /etc /usr /opt /root /var/www /var/spool/cron (data volumes/shares intentionally excluded — scan those separately if relevant)." ""
    fi
  else
    not_available "world-writable file scan needs root or read access to /etc"
  fi
}

check_cron() {
  section "Scheduled Tasks (cron)"
  local suspicious=""
  local cron_files=(/etc/crontab /etc/cron.d/* )
  if $IS_ROOT; then
    for u in $(cut -f1 -d: /etc/passwd 2>/dev/null); do
      local c; c="$(crontab -u "$u" -l 2>/dev/null)"
      [[ -n "$c" ]] && cron_files+=("<user:$u>")
      [[ -n "$c" ]] && suspicious+="$(grep -E 'curl|wget' <<<"$c" | grep -E '\|\s*(ba)?sh' && echo " (^ user: $u)")"
    done
  fi
  local sysfind
  sysfind="$(cat /etc/crontab /etc/cron.d/* 2>/dev/null | grep -Ev '^\s*#|^\s*$')"
  suspicious+=$'\n'"$(grep -E 'curl|wget' <<<"$sysfind" | grep -E '\|\s*(ba)?sh')"
  suspicious="$(echo "$suspicious" | grep -v '^\s*$' || true)"

  if [[ -n "$sysfind" ]]; then
    add_finding "INFO" "System-wide cron entries" "" "$(truncate_output 25 <<<"$sysfind")"
  fi
  if [[ -n "$suspicious" ]]; then
    add_finding "HIGH" "Cron job pipes a download straight into a shell" "A cron entry runs curl/wget piped into sh/bash. This is a common persistence technique for malware, but can also be a legitimate (if risky) install script — verify the source is trusted." "$suspicious"
  fi
  if ! $IS_ROOT; then
    not_available "per-user crontabs (need root to enumerate all users)"
  fi
}

check_docker() {
  section "Container Runtime (Docker)"
  if ! has_cmd docker; then
    not_available "docker (not installed)"
    return
  fi
  if ! docker info >/dev/null 2>&1; then
    add_finding "INFO" "Docker installed but daemon not reachable from this user" "Re-run as root or a user in the docker group for a full container audit." ""
    return
  fi
  local priv
  priv="$(docker ps -q 2>/dev/null | xargs -r docker inspect --format '{{.Name}}: Privileged={{.HostConfig.Privileged}}' 2>/dev/null | grep 'Privileged=true' || true)"
  [[ -n "$priv" ]] && add_finding "HIGH" "Privileged container(s) running" "Privileged containers can access host devices and largely bypass container isolation — equivalent to root on the host in most practical exploit chains. Confirm this is required; drop --privileged and grant specific --cap-add instead if possible." "$priv"

  # docker socket exposed via TCP without TLS
  if has_cmd ss; then
    local dsock
    dsock="$(ss -tlnH 2>/dev/null | grep -E ':(2375)\b')"
    [[ -n "$dsock" ]] && add_finding "CRITICAL" "Docker API exposed on TCP 2375 without TLS" "Unauthenticated root-equivalent access to the Docker daemon. Anyone who can reach this port can run arbitrary containers with host access. Bind to a unix socket, or require TLS client certs (port 2376) and firewall it." "$dsock"
  fi

  local sock_perm
  if [[ -S /var/run/docker.sock ]]; then
    sock_perm="$(stat -c '%a %U:%G' /var/run/docker.sock 2>/dev/null)"
    add_finding "INFO" "Docker socket permissions" "Anyone in the docker group (or root) can control the daemon, which is equivalent to root on the host. Keep the docker group membership tight." "/var/run/docker.sock: $sock_perm"
  fi
}

check_shares() {
  section "File Sharing (Samba / NFS) — NAS relevant"
  local found=false

  if [[ -r /etc/samba/smb.conf ]]; then
    found=true
    local smb; smb="$(grep -Ev '^\s*[#;]|^\s*$' /etc/samba/smb.conf 2>/dev/null)"
    if grep -qiE 'guest ok\s*=\s*yes' <<<"$smb"; then
      add_finding "HIGH" "Samba share(s) allow guest (no-auth) access" "Anyone on the network — and the internet if SMB ports 139/445 are exposed — can read/write these shares with no credentials. Set 'guest ok = no' unless this is intentionally a public share." "$(grep -B5 -i 'guest ok\s*=\s*yes' <<<"$smb" | truncate_output 20)"
    fi
    if grep -qiE '^\s*(server min protocol|min protocol)\s*=\s*NT1' <<<"$smb"; then
      add_finding "HIGH" "SMB1 protocol explicitly allowed" "SMB1 is deprecated and has known critical vulnerabilities (e.g. EternalBlue/WannaCry). Remove this setting or set min protocol to SMB2+." ""
    fi
    add_finding "INFO" "Samba configuration summary" "" "$(truncate_output 30 <<<"$smb")"
  fi

  if [[ -r /etc/exports ]]; then
    local exp; exp="$(grep -Ev '^\s*#|^\s*$' /etc/exports 2>/dev/null)"
    if [[ -n "$exp" ]]; then
      found=true
      if grep -qE '\*\(|(\s|^)everyone(\s|\()' <<<"$exp"; then
        add_finding "HIGH" "NFS export shared with '*' (any host)" "This share is exported to any client that can reach it on the network, with no host restriction. Scope to specific IPs/subnets in /etc/exports." "$exp"
      fi
      if grep -q 'no_root_squash' <<<"$exp"; then
        add_finding "HIGH" "NFS export uses no_root_squash" "Remote root is mapped to local root on this export — a compromised or malicious client can write as root on this filesystem. Remove no_root_squash unless you specifically need it." "$(grep no_root_squash <<<"$exp")"
      fi
      add_finding "INFO" "NFS exports" "" "$exp"
    fi
  fi

  $found || not_available "Samba/NFS config (no smb.conf or exports file found — likely not a file server, or NAS-vendor GUI manages this outside these standard paths, e.g. Synology DSM/TrueNAS web UI)"
}

check_rootkit_scan() {
  section "Rootkit / Malware Scanners"
  if has_cmd rkhunter; then
    add_finding "INFO" "rkhunter is installed" "Not run automatically by this script (can take a long time and touches system state via its database). Run 'rkhunter --check' manually and review its report separately." ""
  elif has_cmd chkrootkit; then
    add_finding "INFO" "chkrootkit is installed" "Run 'chkrootkit' manually and review separately." ""
  else
    add_finding "LOW" "No rootkit scanner installed" "Consider installing rkhunter or chkrootkit for periodic integrity/rootkit checks, especially on an internet-facing host." ""
  fi
}

check_time_logging() {
  section "Time Sync & Logging"
  if systemctl is-active systemd-timesyncd >/dev/null 2>&1 || systemctl is-active chronyd >/dev/null 2>&1 || systemctl is-active ntpd >/dev/null 2>&1; then
    add_finding "PASS" "Time sync service is active" "Accurate time matters for log correlation and TLS/cert validation." ""
  else
    add_finding "LOW" "No active time-sync service detected" "Without NTP, clock drift can break TLS validation and make log timelines unreliable during incident response." ""
  fi
  if systemctl is-active rsyslog >/dev/null 2>&1 || systemctl is-active systemd-journald >/dev/null 2>&1; then
    add_finding "PASS" "System logging service active" "" ""
  else
    add_finding "LOW" "No system logging service detected as active" "Without centralized logs, investigating any future incident becomes much harder." ""
  fi
}

# ===========================================================================
# Main
# ===========================================================================
main() {
  progress "Starting security audit of ${HOSTNAME_STR}..."
  check_system_info
  check_updates
  check_network_exposure
  check_firewall
  check_ssh
  check_fail2ban
  check_users
  check_auth_failures
  check_file_perms
  check_cron
  check_docker
  check_shares
  check_rootkit_scan
  check_time_logging

  { write_header; cat "$FINDINGS_TMP"; } > "$REPORT_MD"

  echo >&2
  progress "Done. ${SEV_COUNT[CRITICAL]} critical, ${SEV_COUNT[HIGH]} high, ${SEV_COUNT[MEDIUM]} medium, ${SEV_COUNT[LOW]} low, ${SEV_COUNT[INFO]} info, ${SEV_COUNT[PASS]} passed."
  progress "Report written to: $REPORT_MD"
}

main "$@"