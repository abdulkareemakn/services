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

# Always re-extract: /opt/caddy/data is disposable, so a regenerated CA would
# otherwise be masked by a stale ./root.crt left over from the previous one.
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
	info "extracting root CA from the running '$CONTAINER' container"
	docker cp "$CONTAINER:$CONTAINER_PATH" "$LOCAL_CRT" >/dev/null \
		|| die "could not copy $CONTAINER_PATH out of $CONTAINER"
elif [ -f "$LOCAL_CRT" ]; then
	info "'$CONTAINER' is not running; using the existing $LOCAL_CRT"
elif docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
	die "'$CONTAINER' exists but is not running. Start it first:
       make up SERVICE=caddy"
else
	die "no root CA found and no '$CONTAINER' container.
       Start the ingress first:
       make up SERVICE=caddy"
fi

command -v openssl >/dev/null 2>&1 || die "openssl is required but not installed"

if ! openssl x509 -in "$LOCAL_CRT" -noout >/dev/null 2>&1; then
	die "$LOCAL_CRT is not a valid PEM certificate"
fi

# openssl prints these with a "subject="/"issuer=" prefix; strip it to compare.
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

[ "$(uname -s)" = "Darwin" ] && { info "macOS detected"; TRUST_MODE=security; }

if [ -z "${TRUST_MODE:-}" ]; then
	if command -v update-ca-trust >/dev/null 2>&1; then
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
		# Arch and Fedora both ship update-ca-trust but read different
		# directories. On Arch an anchor under /etc/pki is never picked up.
		if [ -f /etc/arch-release ]; then
			ANCHOR_DIR=/etc/ca-certificates/trust-source/anchors
			LABEL="p11-kit (Arch)"
		else
			ANCHOR_DIR=/etc/pki/ca-trust/source/anchors
			LABEL="p11-kit (Fedora, RHEL, openSUSE)"
		fi
		REFRESH="update-ca-trust"
		;;
	ca-certificates)
		# Alpine keeps its anchors in the bundle directory itself.
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

# Verify against the bundle the system resolves, not the anchor's own directory:
# a store that accepts the file but ignores it still reports success here.
if [ "$LABEL" != "macOS Keychain" ]; then
	BUNDLE=""
	for b in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do
		if [ -f "$b" ]; then BUNDLE="$b"; break; fi
	done
	[ -n "$BUNDLE" ] || die "no system CA bundle found to verify against"

	if openssl verify -CAfile "$BUNDLE" "$LOCAL_CRT" >/dev/null 2>&1; then
		info "verified: $BUNDLE now trusts this CA"
	else
		die "the anchor is in $ANCHOR_DIR but $BUNDLE still does not trust it.
       The certificate is NOT trusted - browsers will keep warning.
       On Arch the bundle is built from /etc/ca-certificates/trust-source/anchors.
       Try:  sudo trust anchor $LOCAL_CRT && sudo update-ca-trust"
	fi
fi

info ""
info "Check it works:"
info "  curl -sI https://<service>.localhost | head -1"
info ""
info "To remove it later:"
case "$TRUST_MODE" in
	ca-trust)      info "  sudo rm $ANCHOR_DIR/$CERT_NAME.crt && sudo $REFRESH" ;;
	ca-certificates) info "  sudo rm $ANCHOR_DIR/$CERT_NAME.crt && sudo $REFRESH" ;;
	trust)         info "  sudo rm $ANCHOR_DIR/$CERT_NAME.crt && sudo $REFRESH" ;;
	security)      info "  sudo security remove-trusted-cert -d $ANCHOR_DIR/$CERT_NAME.crt" ;;
esac
