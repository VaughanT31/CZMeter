importScripts("parser.js");

self.onmessage = async function (e) {
  try {
    var result = await self.CZLogParser.parseFile(e.data, function (done) {
      self.postMessage({ type: "progress", done: done });
    });
    self.postMessage({ type: "result", result: result });
  } catch (err) {
    self.postMessage({ type: "error", message: String(err) });
  }
};
