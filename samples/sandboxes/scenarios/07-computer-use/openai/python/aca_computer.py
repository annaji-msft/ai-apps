"""Adapter mapping OpenAI computer-use actions to the ACA sandbox control server.

The OpenAI Responses API ``computer_use_preview`` tool emits ``computer_call``
items whose ``action`` field is one of: click, double_click, scroll, type, wait,
screenshot, move, keypress, drag. This class executes each action by POSTing to
the FastAPI control server running **inside** the sandbox (see
``../../desktop-image/control_server.py``).

The control server is reachable via the sandbox's public ``add_port(7000)`` URL.
We never call ``sandbox.exec`` per action — that would add hundreds of ms of
control-plane round-trip per click. The long-lived HTTP control channel keeps
latency dominated by xdotool itself (~10ms) plus model round-trip.
"""

from __future__ import annotations

import base64
import time
from dataclasses import dataclass
from typing import Any

import requests


@dataclass
class ACAComputer:
    """Thin HTTP client for the sandbox control server.

    Attributes:
        base_url:   Public URL of the control server (the URL returned by
                    ``sandbox.add_port(7000, anonymous=True).url``).
        dimensions: Display size, matching the Xvfb geometry started by
                    ``desktop-image/setup.sh``. Sent to the model via the
                    tool definition so it knows where it can click.
        environment: "linux", per OpenAI's tool schema.
    """

    base_url: str
    dimensions: tuple[int, int] = (1280, 800)
    environment: str = "linux"
    timeout: float = 30.0

    # ------------------------------------------------------------------
    # Primitives
    # ------------------------------------------------------------------

    def screenshot(self) -> str:
        """Return a base64-encoded PNG of the current desktop."""
        r = requests.get(f"{self.base_url}/screenshot", timeout=self.timeout)
        r.raise_for_status()
        return r.json()["image_base64"]

    def click(self, x: int, y: int, button: str = "left") -> None:
        self._post("/click", {"x": int(x), "y": int(y), "button": button})

    def double_click(self, x: int, y: int) -> None:
        self._post("/double_click", {"x": int(x), "y": int(y), "button": "left"})

    def move(self, x: int, y: int) -> None:
        self._post("/move", {"x": int(x), "y": int(y)})

    def drag(self, path: list[dict[str, int]]) -> None:
        self._post("/drag", {"path": path, "button": "left"})

    def type(self, text: str) -> None:
        self._post("/type", {"text": text})

    def keypress(self, keys: list[str]) -> None:
        self._post("/key", {"keys": keys})

    def scroll(self, x: int, y: int, scroll_x: int, scroll_y: int) -> None:
        self._post("/scroll", {
            "x": int(x), "y": int(y),
            "scroll_x": int(scroll_x), "scroll_y": int(scroll_y),
        })

    def wait(self, ms: int = 1000) -> None:
        self._post("/wait", {"ms": int(ms)})

    # ------------------------------------------------------------------
    # Dispatch — turn a ``computer_call.action`` from the model into a
    # control-server call. Tolerates both dict and pydantic-style objects.
    # ------------------------------------------------------------------

    def execute(self, action: Any) -> None:
        """Execute one ``computer_call`` action emitted by the model."""
        a = _as_dict(action)
        t = a.get("type")
        if t == "screenshot":
            return  # taking the screenshot is the caller's job
        if t == "click":
            self.click(a["x"], a["y"], a.get("button", "left"))
        elif t == "double_click":
            self.double_click(a["x"], a["y"])
        elif t == "move":
            self.move(a["x"], a["y"])
        elif t == "drag":
            self.drag([_as_dict(p) for p in a["path"]])
        elif t == "type":
            self.type(a["text"])
        elif t == "keypress":
            self.keypress(list(a["keys"]))
        elif t == "scroll":
            self.scroll(a["x"], a["y"], a.get("scroll_x", 0), a.get("scroll_y", 0))
        elif t == "wait":
            self.wait(a.get("ms", 1000))
        else:
            # Unknown action types are non-fatal — log and continue. The
            # model will get a fresh screenshot and can re-plan.
            print(f"    [warn] unknown computer action type: {t}  payload={a}")

    # ------------------------------------------------------------------
    # Convenience: poll until the control server is reachable. ACA's
    # ingress takes a few seconds after add_port() to start routing.
    # ------------------------------------------------------------------

    def wait_until_ready(self, timeout: float = 60.0) -> None:
        deadline = time.monotonic() + timeout
        last_err: Exception | None = None
        while time.monotonic() < deadline:
            try:
                r = requests.get(f"{self.base_url}/healthz", timeout=5.0)
                if r.ok and r.json().get("ok"):
                    return
            except Exception as e:  # noqa: BLE001
                last_err = e
            time.sleep(1.0)
        raise RuntimeError(
            f"control server at {self.base_url} not ready after {timeout:.0f}s "
            f"(last error: {last_err})"
        )

    # ------------------------------------------------------------------

    def _post(self, path: str, payload: dict) -> dict:
        r = requests.post(
            f"{self.base_url}{path}", json=payload, timeout=self.timeout,
        )
        r.raise_for_status()
        return r.json()


def _as_dict(obj: Any) -> dict:
    if isinstance(obj, dict):
        return obj
    # OpenAI SDK returns pydantic-style objects with .model_dump() or .dict().
    for attr in ("model_dump", "dict"):
        fn = getattr(obj, attr, None)
        if callable(fn):
            try:
                return fn()
            except TypeError:
                # Some versions take kwargs (mode="python"); fall through.
                pass
    # Final fallback — best-effort attribute walk.
    return {k: getattr(obj, k) for k in dir(obj) if not k.startswith("_")}


__all__ = ["ACAComputer"]
