# Sensitive Configuration Encryption with age

English | [简体中文](server-library-encryption-format.zh.md)

The server library and proxy listening configuration use standard [age v1](https://age-encryption.org/v1) files through [AgeSwift](https://github.com/qiuyuzhou/AgeSwift). See [ADR-0050](adr/0050-age-encrypted-configuration-storage.md) for the decision and recovery boundaries.

## Files and payloads

Both files live in `~/Library/Application Support/ShadowsocksX-NG2/configuration/`:

| File | Decrypted UTF-8 JSON | Maximum plaintext size |
| --- | --- | --- |
| `catalog.age` | Catalog schema v7: `version`, `rootChildren`, `entries`, `subscriptions`, `favoriteIDs` | 64 MiB |
| `proxy-listening.age` | `{ "version": 1, "configuration": { "local": …, "lan": … } }` | 1 MiB |

The server library contains the entire catalog, subscriptions and ordered favorites, including server passwords, complete plugin options and subscription URLs in their owning records. Listener credentials belong to the separate listening configuration. Runtime JSON, LAN authentication sidecars, user exports and sharing are outside this format's scope.

Writers produce binary age v1, with a single X25519 recipient and no application header, UUID prefix, sidecar index, outer Base64 layer or custom cryptographic container. Readers also accept standard ASCII armor. Saving an armored input writes binary age. JSON schema versions are inside the encrypted payload, independent of the age format version. Readers validate the complete decoded model before publishing it.

An empty catalog payload is:

```json
{
  "entries": [],
  "favoriteIDs": [],
  "rootChildren": [],
  "subscriptions": [],
  "version": 7
}
```

Catalog hierarchy and ordering come from `rootChildren` and group child arrays. Secrets remain ordinary record values, not credential references. Codable models define the full schema; whitespace and object key order carry no meaning.

## Keychain identities

Each store uses its own classic login Keychain Generic Password service:

| File | Service |
| --- | --- |
| `catalog.age` | `com.qiuyuzhou.ShadowsocksX-NG2.server-library.age` |
| `proxy-listening.age` | `com.qiuyuzhou.ShadowsocksX-NG2.proxy-listening.age` |

Each account is a UUID; its value is the UTF-8 standard `AGE-SECRET-KEY-1...` identity, not raw AES bytes. Items do not synchronize and do not use the Data Protection Keychain. Creation grants access only to the current application through a classic Keychain ACL.

The file contains no Keychain account locator. The reader enumerates accounts in the relevant service and tries identities until one decrypts the file. Inaccessible or unrelated candidates do not prevent an accessible matching identity from succeeding. Normal saves reuse the matched identity, cached in the current process. A confirmed reset stores and reads back a new identity before atomically replacing ciphertext; older identities remain available if the commit fails or the process exits midway. Records therefore grow with resets. Identity cleanup and manual rotation are not provided.

Startup/background reads do not request authorization UI. Existing explicit application interaction controls remain in force. Losing a matching identity prevents decryption; changing the file format does not bypass Keychain authorization or provide independent recovery.

## Inspect with standard tools

Install the reference CLI with `brew install age`. In Keychain Access, search for the exact service above and inspect the account UUIDs. Use the system `security` tool to retrieve an identity after system authorization. Replace `ACCOUNT_UUID`; repeat with other accounts into the same identity file if the service contains several identities.

```bash
umask 077
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
security find-generic-password \
  -s com.qiuyuzhou.ShadowsocksX-NG2.server-library.age \
  -a ACCOUNT_UUID -w >> "$workdir/identities.txt"
age --decrypt -i "$workdir/identities.txt" \
  "$HOME/Library/Application Support/ShadowsocksX-NG2/configuration/catalog.age" | jq .
```

For listening configuration, substitute its service and `proxy-listening.age`. Choose one-time authorization when prompted; do not broaden the application's ACL. The identity file is a secret and the output contains configuration credentials. These commands deliberately export a temporary identity for maintenance; the application never writes identities to ordinary files, logs or diagnostic reports. Removal does not promise secure erasure.

Standard age tools can also encrypt JSON to the corresponding `age1...` recipient. Such a file still has to satisfy the application's schema and size checks. Quit the GUI before manually replacing a persistent configuration, since the running app holds committed data in memory. No application-specific decryptor or private-key export UI is required.

## Reads, writes and recovery

Reads limit encoded file size before decryption, accounting for age chunk tags, header allowance and armor overhead; plaintext is checked against its original limit after decryption. Invalid age data, missing identities, authentication failures and invalid JSON fail loading. There is no plaintext fallback or automatic replacement with defaults.

Writes encode and validate the entire value, encrypt in memory, then atomically replace the destination with a ciphertext-only temporary file in the same directory. Directories use `0700`; temporary and destination files use `0600`. The current writer does not explicitly `fsync`, so atomic replacement does not promise power-loss durability. Application state is published only after successful persistence.

The `.age` file takes precedence when present. If absent, an existing corresponding `.enc` or legacy `.json` file causes an unsupported-format error, not fresh initialization. NG2 historical formats are not migrated, read, deleted or used as fallback; old AES and per-item Keychain records are not accessed or cleaned up. A confirmed reset creates the new `.age` file and leaves historical files untouched.

The server library retains retry/unlock and confirmed empty-library creation. Listening configuration retains its startup gate and confirmed reset to defaults with LAN listening disabled. Loading failure or failed reset preserves existing files and running proxy/system-proxy state. The user-initiated legacy ShadowsocksX-NG import remains available.

## Verification and limitations

`AgeConfigurationStorageTests` exercises standard age CLI decryption and encryption in binary and armor for both stores, historical-file rejection, candidate identity selection, failed reset commits, schema/size checks and an isolated real Keychain. The test requires `age` on PATH or in a Homebrew bin directory and an accessible login Keychain.

age protects stored content; file size and timestamps remain visible. It does not provide rollback protection, safe memory erasure, cross-machine identity recovery or an independent password-encrypted backup. The application retains decrypted values and the matching identity until exit.

Source entry points: [EncryptedFileStorage](../ShadowsocksX-NG2/Domain/Credentials/EncryptedFileStorage.swift), [MasterKeyStore](../ShadowsocksX-NG2/Domain/Credentials/MasterKeyStore.swift), [CatalogFileStore](../ShadowsocksX-NG2/Domain/Catalog/CatalogFileStore.swift), [ProxyListeningFileStore](../ShadowsocksX-NG2/Domain/Settings/ProxyListeningFileStore.swift), [AtomicFileWriter](../ShadowsocksX-NG2/Domain/Runtime/AtomicFileWriter.swift).
