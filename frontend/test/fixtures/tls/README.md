# Local TLS fixtures

These certificates and the server private key are public, test-only fixtures.
**Never use them for a deployment or install this certificate authority (CA) on
a personal device.** They let tests check trusted, expired and wrong-host
certificates without depending on a public server.

## What the fixtures cover

The CA signs a server certificate for `localhost` (2018–2120) and an expired
certificate (2000–2001), both using the same test server key. Neither certificate
covers `127.0.0.1`, allowing real hostname-verification tests on the same listener.
The CA private key was discarded after fixture generation with OpenSSL 3.6.4.
No test requires OpenSSL at runtime.

The valid fixture's issuance predates Apple's July 2019 certificate lifetime
limit so macOS can run the same long-lived test fixture as Linux and Android.
This is test data only; production certificates must follow platform requirements.
