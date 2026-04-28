function parseVersion(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
  if (!match) {
    throw new Error(`Invalid version: ${version}`);
  }

  return match.slice(1).map(Number);
}

function compareVersions(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] > right[index]) return 1;
    if (left[index] < right[index]) return -1;
  }
  return 0;
}

function bumpPatch(versionParts) {
  return [versionParts[0], versionParts[1], versionParts[2] + 1].join(".");
}

export function resolveNextVersion(currentVersion, latestTag) {
  const currentParts = parseVersion(currentVersion);
  if (!latestTag) return currentVersion;

  const taggedVersion = latestTag.replace(/^v/, "");
  const taggedParts = parseVersion(taggedVersion);
  const comparison = compareVersions(currentParts, taggedParts);

  if (comparison > 0) return currentVersion;
  return bumpPatch(taggedParts);
}

function readInputValue(argIndex, envKey) {
  const value = process.argv[argIndex];
  if (value) return value;

  const envValue = process.env[envKey];
  return envValue || "";
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const currentVersion = readInputValue(2, "CURRENT_VERSION");
  const latestTag = readInputValue(3, "LATEST_TAG") || null;

  if (!currentVersion) {
    console.error("CURRENT_VERSION is required");
    process.exit(1);
  }

  process.stdout.write(resolveNextVersion(currentVersion, latestTag));
}
