#!/usr/bin/env python3
# Convert one dropped Source issue (.eml) to the markdown the watcher cites.
# Keeps the text/plain body; drops the recipient, tracking links and the mailer footer.
import email
import re
import sys
from email import policy

FOOTER_START = "Was this email useful?"
TRACKING = re.compile(r"<https?://(links\.[^>]*|[^>]*unsubscribe[^>]*)>")
FILLER = "\u034f\u200c\u200b\u00a0\u2007 \t"

src, dst = sys.argv[1], sys.argv[2]
with open(src, "rb") as f:
    msg = email.message_from_binary_file(f, policy=policy.default)
body = msg.get_body(preferencelist=("plain",))
if body is None:
    sys.exit(f"eml-to-md: {src} has no text/plain part")

text = body.get_content().split(FOOTER_START, 1)[0]
text = TRACKING.sub("", text)
lines = [line.rstrip(FILLER) for line in text.splitlines()]
text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()

with open(dst, "w") as f:
    f.write(f"# {msg['Subject']}\n\n")
    f.write(f"From: {msg['From']}  \nDate: {msg['Date']}  \nSource: `{src.rsplit('/', 1)[-1]}`\n\n")
    f.write(text + "\n")
