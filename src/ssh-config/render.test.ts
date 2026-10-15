import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  hostFromTerraformOutput,
  renderHost,
  writeConfig,
  type TerraformOutputs,
} from "./render.js";

const host = {
  alias: "demo-aws",
  hostName: "203.0.113.10",
  user: "ubuntu",
  identityFile: "/home/demo/.ssh/id_ed25519",
  forwardAgent: true,
  localForwards: [3000, 8080],
};

test("renderHost writes an SSH block with forwards", () => {
  const text = renderHost(host);
  assert.match(text, /^Host demo-aws\n/);
  assert.match(text, /HostName 203\.0\.113\.10/);
  assert.match(text, /User ubuntu/);
  assert.match(text, /IdentityFile \/home\/demo\/\.ssh\/id_ed25519/);
  assert.match(text, /ForwardAgent yes/);
  assert.match(text, /LocalForward 3000 127\.0\.0\.1:3000/);
  assert.match(text, /LocalForward 8080 127\.0\.0\.1:8080/);
  assert.doesNotMatch(text, /0\.0\.0\.0/);
});

test("renderHost omits ForwardAgent when it is off", () => {
  const text = renderHost({ ...host, forwardAgent: false, localForwards: [] });
  assert.doesNotMatch(text, /ForwardAgent/);
  assert.doesNotMatch(text, /LocalForward/);
});

test("renderHost rejects a blank alias", () => {
  assert.throws(() => renderHost({ ...host, alias: "demo aws" }), /alias/);
});

test("hostFromTerraformOutput strips the .pub suffix", () => {
  const raw: TerraformOutputs = {
    public_ip: { value: "203.0.113.10" },
    ssh_user: { value: "ubuntu" },
    ssh_public_key_path: { value: "/keys/id_ed25519.pub" },
    forward_ports: { value: [3000] },
    git_auth: { value: "agent" },
  };
  const parsed = hostFromTerraformOutput("demo-aws", raw);
  assert.equal(parsed.identityFile, "/keys/id_ed25519");
  assert.equal(parsed.forwardAgent, true);
  assert.deepEqual(parsed.localForwards, [3000]);
});

test("writeConfig writes mode 600 content to the given path", () => {
  const dir = mkdtempSync(join(tmpdir(), "demo-machines-ssh-"));
  const path = join(dir, "nested", "demo-machines");
  writeConfig(path, [host]);
  const text = readFileSync(path, "utf8");
  assert.match(text, /Host demo-aws/);
});
