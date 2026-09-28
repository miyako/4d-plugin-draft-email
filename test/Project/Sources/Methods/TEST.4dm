//%attributes = {}
var $email : Object
$email:={}
$email.htmlBody:=File:C1566("/RESOURCES/body.html").getText()
$email.textBody:=File:C1566("/RESOURCES/body.txt").getText()
$email.subject:="Confirm project release — April 30, 2026"
$email.attachments:=[]
$email.recipients:=[]
$file:=Folder:C1567(Temporary folder:C486; fk platform path:K87:2).file("attachment.txt")
$file.setText("attachment")
$email.attachments.push($file)
$email.recipients.push("keisuke.miyako@4d.com")

CREATE EMAIL DRAFT($email)