#!/usr/bin/env bash
# Install Caddy's internal root CA into the host trust store.
#
# Trust paths and refresh commands differ per distribution, so detect rather
# than assume. Safe to re-run: it only ever adds or replaces its own anchor.

set -euo pipefail

CERT_NAME="caddy-local"
LOCAL_CRT="./root.crt"
CONTAINER="caddy"
CONTAINER_PATH="/data/caddy/pki/authorities/local/root.crt"

die() { printf '  \033[31merror\033[0m %s\n' "$1" >&2; exit 1; }
info() { printf '  %s\n' "$1"; }

# ── Locate the certificate ───────────────────────────────────────────────────

if [ ! -f "$LOCAL_CRT" ]; then
	if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
		info "extracting root CA from the running '$CONTAINER' container"
		docker cp "$CONTAINER:$CONTAINER_PATH" "$LOCAL_CRT" >/dev/null \
			|| die "could not copy $CONTAINER_PATH out of $CONTAINER"
	elif docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
		die "'$CONTAINER' exists but is not running. Start it first:
       make up SERVICE=caddy"
	else
		die "no root CA found and no '$CONTAINER' container.
       Start the ingress first:
       make up SERVICE=caddy"
	fi
fi

command -v openssl >/dev/null 2>&1 || die "openssl is required but not installed"

# ── Identify the certificate, so a stale copy cannot be installed silently ───

if ! openssl x509 -in "$LOCAL_CRT" -noout >/dev/null 2>&1; then
	die "$LOCAL_CRT is not a valid PEM certificate"
fi

# -subject/-issuer both carry an "subject="/"issuer=" prefix, so strip it
# before comparing or matching.
SUBJECT=$(openssl x509 -in "$LOCAL_CRT" -noout -subject 2>/dev/null | sed 's/^subject=//')
ISSUER=$(openssl x509 -in "$LOCAL_CRT" -noout -issuer 2>/dev/null | sed 's/^issuer=//')

[ "$SUBJECT" = "$ISSUER" ] || die "$LOCAL_CRT is not a self-signed root CA.
       It should be Caddy's own root; found:
       subject: $SUBJECT
       issuer:  $ISSUER"

case "$SUBJECT" in
	*Caddy*) : ;;
	*) die "certificate does not look like Caddy's root CA:
       $SUBJECT" ;;
esac

# ── Detect the platform ──────────────────────────────────────────────────────

[ "$(uname -s)" = "Darwin" ] && { info "macOS detected"; TRUST_MODE=security; }

if [ -z "${TRUST_MODE:-}" ]; then
	if command -v update-ca-trust >/dev/null 2>&1; then
		# Arch, Fedora, RHEL, CentOS, openSUSE — resolves via PATH so the
		# check works regardless of where the binary is installed
		TRUST_MODE=ca-trust
	elif command -v update-ca-certificates >/dev/null 2>&1; then
		TRUST_MODE=ca-certificates
	elif command -v trust >/dev/null 2>&1; then
		TRUST_MODE=trust
	else
		die "no recognised trust store tooling found.
       Install ca-certificates, or add the CA manually:
         openssl x509 -in $LOCAL_CRT -noout -text"
	fi
fi

case "$TRUST_MODE" in
	ca-trust)
		ANCHOR_DIR=/etc/pki/ca-trust/source/anchors
		REFRESH="update-ca-trust"
		LABEL="p11-kit (Arch, Fedora, RHEL, openSUSE)"
		;;
	ca-certificates)
		# Distinguish Alpine, which keeps anchors in the system bundle directly.
		if [ -f /etc/alpine-release ]; then
			ANCHOR_DIR=/etc/ssl/certs
			LABEL="Alpine"
		else
			ANCHOR_DIR=/usr/local/share/ca-certificates
			LABEL="Debian, Ubuntu, Mint, Gentoo"
		fi
		REFRESH="update-ca-certificates"
		;;
	trust)
		ANCHOR_DIR=/etc/ssl/certs
		REFRESH="trust extract-compat"
		LABEL="p11-kit trust(1)"
		;;
	security)
		ANCHOR_DIR="macOS Keychain"
		REFRESH="security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain"
		LABEL="macOS Keychain"
		;;
esac

info "certificate : $SUBJECT"
[ "$LABEL" = "macOS Keychain" ] || info "trust store : $LABEL ($ANCHOR_DIR)"
[ "$LABEL" = "macOS Keychain" ] || info "refresh     : $REFRESH"

# ── Install ──────────────────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
	die "needs root. Re-run with sudo:
       sudo $0 $*"
fi

if [ "$TRUST_MODE" = "security" ]; then
	$REFRESH "$LOCAL_CRT" || die "keychain install failed"
	info "installed to the system keychain"
else
	mkdir -p "$ANCHOR_DIR"
	install -m 0644 "$LOCAL_CRT" "$ANCHOR_DIR/$CERT_NAME.crt"
	$REFRESH >/dev/null 2>&1 || die "$REFRESH failed"
	info "installed to $ANCHOR_DIR/$CERT_NAME.crt"
fi

# ── Verify ───────────────────────────────────────────────────────────────────

if openssl verify -CApath "$(dirname "$ANCHOR_DIR")" "$LOCAL_CRT" >/dev/null 2>&1; then
	info "verified against the system trust store"
else
	info "note: could not self-verify (some distros store anchors in a bundle)."
	info "test with: curl -sI https://memos.localhost | head -1"
fi

info ""
info "Check it works:"
info "  curl -sI https://memos.localhost | head -1"
info ""
info "To remove it later:"
case "$TRUST_MODE" in
	ca-trust)      info "  sudo rm $ANCHOR_DIR/$CERT_NAME.crt && sudo $REFRESH" ;;
	ca-certificates) info "  sudo rm $ANCHOR_DIR/$CERT_NAME.crt && sudo $REFRESH" ;;
	trust)         info "  sudo rm $ANCHOR_DIR/$CERT_NAME.crt && sudo $REFRESH" ;;
	security)      info "  sudo security remove-trusted-cert -d $ANCHOR_DIR/$CERT_NAME.crt" ;;
esac