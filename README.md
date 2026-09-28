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
