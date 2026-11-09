# 4d-plugin-draft-email

Draft an HTML (or plain-text) email with attachments, using the macOS
**Mail.app** compose window — ready for the user to review, edit, and send
themselves. The plugin never sends anything on its own; it only opens a
prefilled draft.

- **Platform:** macOS only (uses `NSSharingService` / Mail.app). Not available
  on Windows or Server.
- **Thread safety:** the command can be called from any process, worker, or
  preemptive thread — it internally hands the actual Mail.app interaction
  back to the main thread.
- **Plugin ID:** 20000

---

## Table of contents

- [Installation](#installation)
- [Commands](#commands)
  - [CREATE EMAIL DRAFT](#create-email-draft)
- [The `options` object](#the-options-object)
- [Behavior notes](#behavior-notes)
- [Error handling](#error-handling)
- [Sample code](#sample-code)
- [Version history](#version-history)

---

## Installation

Copy the `Mail.bundle` plugin into your 4D application's `Plugins` folder (or
your project's `Plugins` folder for a project-specific install), then restart
4D. No further configuration or license activation is required.

---

## Commands

### CREATE EMAIL DRAFT

Opens a new Mail.app compose window, prefilled with the subject, body,
recipients, and attachments you specify. The user sees a normal, editable
Mail draft — they choose whether to send it, save it, or discard it.

#### Syntax

```
CREATE EMAIL DRAFT(options)
```

| Parameter | Type   | Description                                            |
|-----------|--------|---------------------------------------------------------|
| `options` | Object | Draft content. See [The `options` object](#the-options-object) below. |

There is no return value.

#### Availability

| Platform | Supported |
|----------|-----------|
| macOS    | ✅        |
| Windows  | ❌        |
| Server   | ❌ (no interactive Mail.app session) |

---

## The `options` object

All properties are optional — pass only what you need. Anything you omit is
simply left blank in the draft (e.g. the user gets an empty subject line, or
no attachments).

| Property      | Type              | Description                                                                                   |
|---------------|-------------------|-----------------------------------------------------------------------------------------------|
| `subject`     | Text              | The email subject line.                                                                       |
| `htmlBody`    | Text              | HTML source for the body. Rendered as rich text in the draft (formatting, links, images, etc.). |
| `textBody`    | Text              | Plain-text body. If both `htmlBody` and `textBody` are given, **both** are inserted as separate items in the draft — Mail.app will generally keep the HTML version and may fold the plain text in as a second block, so in practice you should pass **one or the other**, not both. |
| `attachments` | Collection of `4D.File` | Files to attach. Build each entry with `File` (`C1566`), e.g. `File("/path/to/file.pdf")`. |
| `recipients`  | Collection of Text | Email addresses for the **To** field, e.g. `["alice@example.com"; "bob@example.com"]`. |

> **Note on `htmlBody`:** pass the raw HTML *source* (a text string), not a
> pre-rendered attributed string — the plugin takes care of turning it into
> rich text internally. Malformed HTML degrades gracefully: if it can't be
> parsed, that part of the body is simply omitted rather than causing an
> error.

---

## Behavior notes

- **Nothing is sent automatically.** `CREATE EMAIL DRAFT` only opens/prepares
  a compose window; a human still has to click Send in Mail.app.
- **Mail.app must be configured** with at least one account on the machine
  running the command; otherwise macOS will prompt the user to set one up
  before a draft can be composed.
- **Attachments** must be files that exist and are readable at the time the
  command runs — pass a `4D.File` object (from `File`/`Folder`), not just a
  path string.
- Calling the command with an empty or missing `options` object is a silent
  no-op — no draft is opened, and no error is raised.
- The command is safe to call from a worker process, a preemptive method, or
  the main process alike.

---

## Error handling

`CREATE EMAIL DRAFT` does not raise a 4D error and does not return a value.
If you need to confirm delivery/user follow-through, that has to happen
outside the plugin (e.g. ask the user to confirm, since 4D cannot detect
whether they clicked Send).

---

## Sample code

### Minimal — plain text only

```4d
var $email : Object
$email:={}
$email.subject:="Weekly status"
$email.textBody:="Everything is on track for Friday's release."
$email.recipients:=["team@example.com"]

CREATE EMAIL DRAFT($email)
```

### Full example — HTML body with an attachment

```4d
var $email : Object
var $file : 4D.File

$email:={}
$email.htmlBody:=File("/RESOURCES/body.html").getText()
$email.subject:="Confirm project release — April 30, 2026"
$email.attachments:=[]
$email.recipients:=[]

$file:=Folder(fk temporary folder).file("attachment.txt")
$file.setText("attachment")

$email.attachments.push($file)
$email.recipients.push("keisuke.miyako@4d.com")

CREATE EMAIL DRAFT($email)
```

### Multiple recipients and attachments

```4d
var $email : Object
var $invoice; $logo : 4D.File

$invoice:=File("/RESOURCES/invoice.pdf")
$logo:=File("/RESOURCES/logo.png")

$email:={}
$email.subject:="Invoice #4821"
$email.htmlBody:="<p>Hi there,</p><p>Please find your invoice attached.</p>"
$email.attachments:=[$invoice; $logo]
$email.recipients:=["billing@clientco.com"; "accounts@clientco.com"]

CREATE EMAIL DRAFT($email)
```

---

## Maintainer workflows

**Bump version** is manual and source-only. Select the intended branch in
Actions and choose `patch`, `minor`, or `major`. It validates the selected
immutable commit, all six project and target configurations, source plist and
localized display metadata before changing anything. It commits only those
three source files, with the Copilot co-author trailer. No tag, release, build,
or workflow dispatch is produced. Run **Build** separately on the resulting
branch commit; Build has no inputs beyond Actions' branch selector.

The bump requires a clean checkout and the selected branch's exact remote SHA.
An executable pre-push guard is mandatory both initially and immediately before
push. The guard checks Git's advertised old SHA, literal new commit SHA, exact
target, one direct parent, and exactly one update. Advance, rewind, deletion,
and even a concurrent identical-result push fail closed. Push is non-force,
with both `push.followTags=false` and `--no-follow-tags`.

Build checks out `github.sha` in both jobs. Source metadata, not a supplied tag
or branch name, determines `vX.Y.Z`, `Mail-X.Y.Z.zip`, and `Mail-X.Y.Z.dmg`.
A constant repository-wide publication concurrency group serializes builds
across branches without cancellation. Early availability checks and a second
check after every native/signing/notarization/stapling gate reject any existing
remote tag or matching draft/published release. Authenticated release pages
are validated in full, including later pages; API/authentication/404/network
or malformed responses abort rather than imply availability.

Publication uses separate create-only requests: POST a new `git/refs` tag at
the selected SHA, verify that remote ref, POST a new public non-prerelease
release named after the tag with the original empty body/no generated notes,
then POST each asset to that newly returned release ID. It never reuses,
updates, deletes, clobbers, rolls back, or retries publication state.

### Version authority and migration evidence

The original bump workflow was introduced in
`6cb499a9dbde3a0bfcc2f64fb2e50a6982b17e34` (`mv`). Rename-follow history for both
workflow files ends there; the parent has no earlier bump/release workflow.
Its header explicitly promises to force-write **MARKETING_VERSION and
CURRENT_PROJECT_VERSION**, plus plist short/build versions, from one version.
This explicit coordinated promise overrides the body's buggy marketing-first,
current-only-fallback implementation; it is not evidence of an independent
build counter. At migration intake, all six marketing values and the actual
source `Info.plist` short version were `1.0.3`, while six current values and
the copied localized display strings remained `1.0.0`.

The migration repairs only that proven drift to the **existing `1.0.3`**, with
no version increment. The source plist has no `CFBundleVersion`; that absence
is preserved. `INFOPLIST_FILE = Info.plist` in all three target configurations
and the Resources phase's `English.lproj/InfoPlist.strings` identify the actual
copied metadata. The latter's CR-only endings and `Copyright 2025 miyako.`
are preserved. Future bumps preserve BOMs, individual line endings (including
mixed endings), file modes, formatting, supported build references, absent
optional keys and unrelated bytes. Duplicate/malformed keys, unresolved or
cyclic references and drift are rejected before writes. Committed bundles,
archives, dependencies, 4D data/schema and counters are never version inputs.

The full pinned prior-art snapshots used for the adaptation are:

- `miyako/4d-plugin-native-encoding-detection@c42ca565857f674bde5ea6ed3435c87375eda4a7`:
  coordinated six-configuration metadata, strict localized tokenizer,
  advertised-SHA guard and create-only lifecycle.
- `miyako/4d-plugin-file-information@19848973601acfd3a2b5070230fa40cdc7e4edb2`:
  malformed-key rejection and UTF-16/binary built localized metadata checks.
  Its three-configuration and explicit i386-exclusion contract are not Mail's.
- `miyako/4d-plugin-common-string-algorithm@2606a68201866ec9fcbb38b51462d79215f504ef`
  and corrected
  `miyako/4d-plugin-window-button@3f14facb9aaaaff0e22eeb8e07531163680c3a8a`:
  independent-build/reference counterexamples, deliberately not applied to
  Mail's explicit coordinated authority.

### Native contract and safety changes

Despite its old Windows-first comment, the original release had **only a macOS
job**. That is preserved: `macos-latest`, Mail project/target, configuration
`Default`, `arm64 x86_64`, `ONLY_ACTIVE_ARCH=NO`, and the existing deployment
override `11.0` (not silently modernized to the project's `11.5`). Native
toolchains, dependencies, frameworks, resources and Xcode build phases are
unchanged. Committed Windows64 files remain in the packaged bundle without
inventing a Windows build. The original required both macOS slices, but had
no explicit i386 rejection; no unrelated architecture policy is added.
Required slices are checked with `lipo -verify_arch`: substring matching
could previously mistake `arm64e` or `x86_64h` for the required slices.

The old workflow could select a committed stale binary if Xcode built
elsewhere. Build now removes only the exact old macOS executable, copied
plist/localization, signature and known intermediate directories, pins
`CONFIGURATION_BUILD_DIR` to the verified `test/Plugins` location, and checks
built metadata against selected source. It never recursively searches for
an output or deletes the whole bundle; QuickLook, other resources and
cross-platform files survive. Both notarization responses must explicitly
report JSON `status: Accepted` before DMG stapling and publication.

Signing/import, verification, ZIP/DMG formats and stapling retain the original
commands and secret **names**: `APPLE_DEVELOPER_ID_CERTIFICATE`,
`APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`,
`NOTARYTOOL_APPLE_ID`, `NOTARYTOOL_TEAM_ID`, and `NOTARYTOOL_PASSWORD`.
There were no release branch restrictions to remove. The unrelated Jekyll
workflow retains its existing `main` push/manual triggers and permissions;
its checkout is also pinned to `github.sha`, like every other checkout.

### Partial-publication recovery

Failure may leave a new tag, a public release, or only some uploaded assets.
These are deliberately retained and the workflow reports the error; a rerun
of the same source version must refuse them. Inspect the failed run, exact
tag SHA, release ID and asset list manually. Decide explicitly whether to
complete that release outside this automation or leave it and bump a new
source version. Do not expect this workflow to repair, delete or overwrite
existing publication state. Re-dispatch Bump if the selected branch moved;
do not force-push a failed bump.

### Offline regression checks

Run `actionlint` and
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/tests -v`.
The suites use disposable source copies, real local bare Git remotes, fake
GitHub API responses, and closed-PATH native command stubs. Also run the
entire suite in a disposable copy after a source-only bump to catch
intake-version assumptions. No real native build, signing, notarization,
4D execution or GitHub publication is needed.

## Version history

**Current release**
- Fixed a crash that occurred whenever `recipients` contained two or more
  addresses (the draft window could fail to open, or 4D could crash
  outright).
- Fixed a case where a draft with zero recipients silently never received
  its `recipients` list.
- Hardened the command against malformed input (invalid HTML, non-UTF-8
  text) — these cases now degrade gracefully (that piece of content is
  omitted) instead of risking a crash.
- Improved reliability of HTML body rendering when the command is called
  from a worker process or preemptive method.
- Fixed several internal memory leaks that could accumulate with heavy or
  repeated use of the command over a long-running 4D session.
