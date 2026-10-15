import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";

import {
  hostFromTerraformOutput,
  writeConfig,
  type SshHost,
  type TerraformOutputs,
} from "./render.js";

const { values } = parseArgs({
  options: {
    "from-terraform": { type: "boolean", default: false },
    alias: { type: "string" },
    "host-name": { type: "string" },
    user: { type: "string" },
    "identity-file": { type: "string" },
    "forward-agent": { type: "boolean", default: false },
    "local-forward": { type: "string", multiple: true, default: [] },
    out: { type: "string" },
  },
  strict: true,
});

const alias = values.alias;
const out = values.out;
if (alias === undefined || out === undefined) {
  throw new Error("alias and out are required");
}

let host: SshHost;
if (values["from-terraform"]) {
  const raw = JSON.parse(readFileSync(0, "utf8")) as TerraformOutputs;
  host = hostFromTerraformOutput(alias, raw);
} else {
  const hostName = values["host-name"];
  const user = values.user;
  const identityFile = values["identity-file"];
  if (hostName === undefined || user === undefined || identityFile === undefined) {
    throw new Error("host-name, user, and identity-file are required");
  }
  host = {
    alias,
    hostName,
    user,
    identityFile,
    forwardAgent: values["forward-agent"],
    localForwards: values["local-forward"].map((port: string) => Number(port)),
  };
}

writeConfig(out, [host]);
console.log(out);
