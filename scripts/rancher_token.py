#!/usr/bin/env python3
"""Mint a Rancher API token (for TF_VAR_rancher_token / CI) and print it to stdout.

Logs in to Rancher's local auth provider, then creates an API token. Only the token is written
to stdout; diagnostics go to stderr, so command substitution is safe:

    python3 scripts/rancher_token.py --url https://rancher-... --user admin --password '...'
    export TF_VAR_rancher_token="$(RANCHER_PASSWORD=... python3 scripts/rancher_token.py --url https://rancher-...)"

(./scripts/rancher_token.py also works; the file is executable.)

Every option can also come from an environment variable (the flag wins):
    --url / RANCHER_URL            required
    --user / RANCHER_USER          default: admin
    password: RANCHER_PASSWORD, or --password-stdin, or an interactive prompt.
              (--password exists but is visible in the process list; avoid it.)
    --ttl-ms / TTL_MS              token lifetime in ms; 0 = non-expiring. default: 86400000 (24h)
    --description / DESCRIPTION    default: cli

Rancher uses a self-signed cert in this platform, so TLS verification is off by default.
Use --verify-tls once Rancher has a real certificate.
"""
import argparse
import getpass
import json
import os
import ssl
import sys
import urllib.error
import urllib.request


def env_default(name, fallback=None):
    return os.environ.get(name, fallback)


def parse_args(argv):
    p = argparse.ArgumentParser(description="Mint a Rancher API token and print it.")
    p.add_argument("--url", default=env_default("RANCHER_URL"), help="Rancher URL (env RANCHER_URL)")
    p.add_argument("--user", default=env_default("RANCHER_USER", "admin"), help="login user (default: admin)")
    pw = p.add_mutually_exclusive_group()
    pw.add_argument("--password", default=None, help="password (visible in ps; prefer env or stdin)")
    pw.add_argument("--password-stdin", action="store_true", help="read the password from stdin")
    p.add_argument("--ttl-ms", type=int, default=int(env_default("TTL_MS", "86400000")),
                   help="token lifetime in ms; 0 = non-expiring (default: 24h)")
    p.add_argument("--description", default=env_default("DESCRIPTION", "cli"), help="token description")
    p.add_argument("--timeout", type=int, default=30, help="HTTP timeout in seconds (default: 30)")
    p.add_argument("--verify-tls", action="store_true", help="verify the Rancher TLS certificate")
    args = p.parse_args(argv)

    if not args.url:
        p.error("--url or RANCHER_URL is required")
    if args.ttl_ms < 0:
        p.error("--ttl-ms must be >= 0")
    args.url = args.url.rstrip("/")

    if args.password is None:
        if args.password_stdin:
            args.password = sys.stdin.readline().rstrip("\n")
        elif env_default("RANCHER_PASSWORD"):
            args.password = os.environ["RANCHER_PASSWORD"]
        elif sys.stdin.isatty():
            args.password = getpass.getpass("Rancher password: ", stream=sys.stderr)
    if not args.password:
        p.error("password required: set RANCHER_PASSWORD, use --password-stdin, or run interactively")
    return args


def post(url, body, ctx, timeout, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"error: {url} returned HTTP {e.code} {e.reason}")
    except (urllib.error.URLError, TimeoutError) as e:
        raise SystemExit(f"error: cannot reach {url}: {getattr(e, 'reason', e)}")


def main(argv=None):
    args = parse_args(argv)
    ctx = ssl.create_default_context()
    if not args.verify_tls:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

    login = post(
        f"{args.url}/v3-public/localProviders/local?action=login",
        {"username": args.user, "password": args.password},
        ctx, args.timeout,
    )
    login_token = login.get("token")
    if not login_token:
        raise SystemExit("error: login failed (check --url / credentials)")

    created = post(
        f"{args.url}/v3/token",
        {"type": "token", "description": args.description, "ttl": args.ttl_ms},
        ctx, args.timeout, token=login_token,
    )
    api_token = created.get("token")
    if not api_token:
        raise SystemExit("error: token creation failed")
    print(api_token)


if __name__ == "__main__":
    main()
