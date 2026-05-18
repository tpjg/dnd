export function set_timeout(ms, callback) {
  globalThis.setTimeout(() => callback(), ms);
}
