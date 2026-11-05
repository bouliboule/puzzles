// Module worker: generates puzzles off the main thread.
// Message in: { id, name, params }  Message out: { id, gameId } or { id, error }
const modules = new Map();

async function getModule(name) {
  let p = modules.get(name);
  if (!p) {
    p = import(`../wasm/${name}.js`).then(m => m.default()).then(M => {
      M.cwrap('pz_init', null, ['number'])(0);
      return { generate: M.cwrap('pz_generate', 'string', ['string']) };
    });
    modules.set(name, p);
  }
  return p;
}

self.onmessage = async (e) => {
  const { id, name, params } = e.data;
  try {
    const m = await getModule(name);
    const gameId = m.generate(params);
    if (!gameId) throw new Error('Invalid parameters: ' + params);
    self.postMessage({ id, gameId });
  } catch (err) {
    self.postMessage({ id, error: String(err && err.message || err) });
  }
};
