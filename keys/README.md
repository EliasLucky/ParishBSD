# ParishBSD release keys

- `release-key.asc` - the public Ed25519 release key. It signs the
  `*.sha256.asc` and `*.sha512.asc` files next to each ISO.
- `pkg.pub` - the public key for the `pkg` repository. Generated with
  `openssl genrsa` or `pkg-key`; **not** a GPG key. `pkg` uses its own
  signature format.

## Verifying an ISO

    gpg --import keys/release-key.asc
    gpg --verify ParishBSD-1.0.5-amd64.iso.sha256.asc \
                 ParishBSD-1.0.5-amd64.iso.sha256
    sha256 -c ParishBSD-1.0.5-amd64.iso.sha256

## Signing

The secret key is never in this repository. `build.sh --sign` requires
`PARISHBSD_SIGNING_KEY` to name a key already present in the builder’s
keyring.