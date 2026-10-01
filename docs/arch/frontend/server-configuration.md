# Native server configuration

Android, iOS, macOS, Linux and Windows select their server at runtime. A new native
installation opens server setup before authentication. The user enters an HTTP(S)
base address, including any port or installation path, and presses Connect. The
app checks the existing unauthenticated readiness endpoint and saves the address
only after the server reports ready. Redirects and unrelated response bodies are
rejected. The request has an eight-second deadline and an eight-KiB response limit.
The probe owns its client and closes it on success, failure or timeout.

The web app keeps its existing browser-origin or build-time endpoint. It has no
server selector. Native builds can still supply `API_BASE_URL` as an initial
development default; a saved address takes precedence. Ordinary native startup
restores the address without probing, so a temporary outage does not remove the
configuration or saved credentials. Failed or corrupt preference reads open a
recoverable setup screen rather than silently selecting another server.

## Ownership and boundaries

The `server` domain defines canonical immutable addresses, failures and a small
repository port. Its data repository combines a `SharedPreferencesAsync` source
with a generated System API readiness source. The nonsecret preference uses
`domabas.server.v1`; credentials continue to use platform secure storage. The
presentation Cubit owns loading, checking and saving. A pending save retains its
operation slot even after the storage-status deadline, preventing a later write
from overtaking it. Completions after Cubit disposal cannot select a server.

`NativeServerApp` is the native composition root. It owns the configuration and
appearance Cubits for the entire app lifetime. A canonical server address keys
the child that owns `AppDependencies` and `DomabasApp`. Changing the address
replaces public transport, authentication, protected navigators, realtime,
document resources, uploads and scanner coordination. No existing client's
base URL or bearer is mutated. Old callbacks cannot install a session in the
replacement app. Appearance remains unchanged during the transition.

Session credentials and scanner drafts already include the server origin and
base path in their storage scope. Switching leaves them attached to their
original server. Returning to that server asks it to validate its saved session.
Changing servers is not remote logout; users can explicitly sign out first when
they want to remove their saved sign-in.

The selector is available on authentication, session recovery and initial-password
screens, and under Settings → Server in the workspace. It is a local preference
available before authentication, grants no namespace authority, and adds no
backend claim or HTTP endpoint. Existing authorization checks still apply to
every authenticated operation.

All native build modes support HTTP and HTTPS servers. For a LAN installation,
enter an address such as `http://192.168.0.230:8088`; use the published web port
or the API's reachable port. The iOS simulator can reach the Mac at
`http://localhost:8080`; Android emulators use `http://10.0.2.2:8080`. Physical
devices need a reachable server hostname or LAN address and must allow local
network access when the operating system asks. HTTP does not encrypt traffic;
HTTPS remains available with normal certificate validation.

For a self-hosted Android server with a private or self-signed CA, install that
CA through Android Settings → Security → Encryption & credentials → Install a
certificate → CA certificate (the names vary by device). Restart Domabas, then
connect using the hostname covered by the server certificate. The app trusts
user-installed CAs in release builds too; certificate expiry and hostname checks
remain enabled. A certificate installed only for Wi-Fi or as a client identity
does not establish server trust. Restart after removing a CA as well. See
[Android certificate trust](platforms.md#android-certificate-trust).

See [platforms and transport](platforms.md) for client construction and the
[testing guide](../../development/testing.md) for validation commands.
