import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export type SshHost = {
  alias: string;
  hostName: string;
  user: string;
  identityFile: string;
  forwardAgent: boolean;
  localForwards: number[];
};

export type TerraformOutputValue<T> = { value: T };

export type TerraformOutputs = {
  public_ip: TerraformOutputValue<string>;
  ssh_user: TerraformOutputValue<string>;
  ssh_public_key_path: TerraformOutputValue<string>;
  forward_ports: TerraformOutputValue<number[]>;
  git_auth: TerraformOutputValue<string>;
};

function requireToken(label: string, value: string): string {
  if (value.length === 0 || /\s/.test(value)) {
    throw new Error(`${label} must be a single token`);
  }
  return value;
}

export function renderHost(host: SshHost): string {
  const alias = requireToken("alias", host.alias);
  const hostName = requireToken("hostName", host.hostName);
  const user = requireToken("user", host.user);
  const identityFile = requireToken("identityFile", host.identityFile);
  const lines = [
    `Host ${alias}`,
    `  HostName ${hostName}`,
    `  User ${user}`,
    `  IdentityFile ${identityFile}`,
    "  IdentitiesOnly yes",
    "  StrictHostKeyChecking accept-new",
  ];
  if (host.forwardAgent) {
    lines.push("  ForwardAgent yes");
  }
  for (const port of host.localForwards) {
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new Error(`local forward port out of range: ${port}`);
    }
    lines.push(`  LocalForward ${port} 127.0.0.1:${port}`);
  }
  return `${lines.join("\n")}\n`;
}

export function renderConfig(hosts: SshHost[]): string {
  return hosts.map((host) => renderHost(host)).join("\n");
}

export function writeConfig(path: string, hosts: SshHost[]): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, renderConfig(hosts), { mode: 0o600 });
}

export function hostFromTerraformOutput(alias: string, raw: TerraformOutputs): SshHost {
  const publicKey = raw.ssh_public_key_path.value;
  const identityFile = publicKey.endsWith(".pub") ? publicKey.slice(0, -4) : publicKey;
  return {
    alias,
    hostName: raw.public_ip.value,
    user: raw.ssh_user.value,
    identityFile,
    forwardAgent: raw.git_auth.value === "agent",
    localForwards: raw.forward_ports.value,
  };
}
