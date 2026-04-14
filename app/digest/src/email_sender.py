from __future__ import annotations

import os

from azure.communication.email import EmailClient


class EmailSender:
    def __init__(self) -> None:
        self._client = EmailClient.from_connection_string(os.environ["ACS_CONNECTION_STRING"])
        self._sender = os.environ["ACS_SENDER"]

    def send(self, to: str, display_name: str, subject: str, html: str, plain: str) -> None:
        poller = self._client.begin_send({
            "senderAddress": self._sender,
            "recipients": {"to": [{"address": to, "displayName": display_name}]},
            "content": {"subject": subject, "html": html, "plainText": plain},
        })
        result = poller.result()
        if result["status"] != "Succeeded":
            raise RuntimeError(f"ACS send failed: {result}")
