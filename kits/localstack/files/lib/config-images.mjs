// Prints the image of each container in an lstk config, one per line.
//
// lstk reads its config through viper, which ignores the case of keys, so
// this script also matches "containers" and "image" in any case. A parse
// error goes to stdout, and the script exits 2, so that the caller can show
// the reason.
//
// Usage: node config-images.mjs CONFIG
import { readFileSync } from "node:fs";
import { parse } from "smol-toml";

const CONTAINERS_KEY = "containers";
const IMAGE_KEY = "image";

function valuesOf(table, key) {
  return Object.entries(table)
    .filter(([name]) => name.toLowerCase() === key)
    .map(([, value]) => value);
}

function containerTables(config) {
  return valuesOf(config, CONTAINERS_KEY)
    .flatMap((value) => (Array.isArray(value) ? value : [value]))
    .filter((table) => table !== null && typeof table === "object");
}

// A value that is not a string is printed as JSON, so the caller sees an
// image that it cannot trust instead of no image.
function imagesOf(config) {
  return containerTables(config)
    .flatMap((table) => valuesOf(table, IMAGE_KEY))
    .map((image) => (typeof image === "string" ? image : JSON.stringify(image)));
}

const path = process.argv[2];
try {
  imagesOf(parse(readFileSync(path, "utf8"))).forEach((image) => console.log(image));
} catch (error) {
  console.log(`${path} is not valid TOML (${error.message.split("\n")[0]}).`);
  process.exit(2);
}
