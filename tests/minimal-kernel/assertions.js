"use strict";
const original = require("node:assert/strict");
const counts = { functional: 0, browser: 0 }; let scope = "functional";
const assert = new Proxy(original, {
  apply(target, receiver, args) { counts[scope]++; return Reflect.apply(target, receiver, args); },
  get(target, key) { const value = Reflect.get(target, key); return typeof value === "function" ? (...args) => { counts[scope]++; return Reflect.apply(value, target, args); } : value; }
});
module.exports = { assert, counts, setScope(value) { const previous = scope; scope = value; return previous; } };
