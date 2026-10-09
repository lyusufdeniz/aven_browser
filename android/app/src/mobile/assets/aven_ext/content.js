(function () {
  const page = window.wrappedJSObject;
  if (!page || page.__avenBridge) return;
  page.__avenBridge = true;

  function define(name) {
    const post = exportFunction(function (data) {
      browser.runtime.sendMessage({
        type: "channel",
        name: name,
        data: String(data),
      });
    }, page);
    const api = new page.Object();
    api.postMessage = post;
    page[name] = api;
  }

  define("AvenVideo");
  define("AvenPopup");
  define("AvenField");
})();
