---
layout: default
---

![version](https://img.shields.io/badge/version-20%2B-E23089)
![platform](https://img.shields.io/static/v1?label=platform&message=mac-intel%20|%20mac-arm&color=blue)
[![license](https://img.shields.io/github/license/miyako/4d-plugin-draft-email)](LICENSE)
![downloads](https://img.shields.io/github/downloads/miyako/4d-plugin-draft-email/total)

# 4d-plugin-draft-email

## Usage

```4d
var $email : Object
$email:={}
$email.htmlBody:=File("/RESOURCES/body.html").getText()
$email.textBody:=File("/RESOURCES/body.txt").getText()
$email.subject:="Confirm project release — April 30, 2026"
$email.attachments:=[]
$email.recipients:=[]
$file:=Folder(Temporary folder; fk platform path).file("attachment.txt")
$file.setText("attachment")
$email.attachments.push($file)
$email.recipients.push("keisuke.miyako@4d.com")

CREATE EMAIL DRAFT($email)
```
