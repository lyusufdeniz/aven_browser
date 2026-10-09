let port = null;
let attempts = 0;

function connect() {
  if (attempts >= 4) return;
  attempts += 1;
  try {
    port = browser.runtime.connectNative("aven");
  } catch (e) {
    port = null;
    setTimeout(connect, 1500);
    return;
  }
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 1500);
  });
  port.onMessage.addListener(async (msg) => {
    if (!msg || msg.type !== "eval" || !port) return;
    const id = msg.id;
    try {
      const tabs = await browser.tabs.query({ active: true });
      const tabId = tabs[0] && tabs[0].id;
      if (tabId == null) {
        port.postMessage({ type: "evalResult", id: id, error: "no-tab" });
        return;
      }
      const results = await browser.scripting.executeScript({
        target: { tabId: tabId },
        world: "MAIN",
        injectImmediately: true,
        func: (source) => {
          try {
            return (0, eval)(source);
          } catch (err) {
            return { __avenError: String(err) };
          }
        },
        args: [msg.code || ""],
      });
      const value = results && results[0] ? results[0].result : null;
      if (!port) return;
      port.postMessage({ type: "evalResult", id: id, value: value });
    } catch (err) {
      if (port) port.postMessage({ type: "evalResult", id: id, error: String(err) });
    }
  });
}

browser.runtime.onMessage.addListener((msg) => {
  if (port && msg && msg.type === "channel") port.postMessage(msg);
});

connect();
