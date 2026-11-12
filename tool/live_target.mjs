/**
 * Shared gate for operator tools that can read or write a live Firebase project.
 *
 * Dry-run is the default. A live write is refused unless every one of these is true:
 *   --project tranyx-app --allow-prod --apply
 *   and GOOGLE_APPLICATION_CREDENTIALS or TARGET_GOOGLE_APPLICATION_CREDENTIALS
 *   points at a service-account JSON file.
 * Emulator writes stay available when FIRESTORE_EMULATOR_HOST is set.
 * tranyx-uat is never a target. tranyx-dev is never upgraded and is not a live-write target.
 */

export function flagValue(argv, name) {
  const i = argv.indexOf(name);
  if (i < 0) return '';
  return argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : '';
}

export function parseLiveArgs(argv) {
  return {
    apply: argv.includes('--apply'),
    allowProd: argv.includes('--allow-prod'),
    project: flagValue(argv, '--project'),
  };
}

export function emulatorHost(env = process.env) {
  const host = env.FIRESTORE_EMULATOR_HOST || '';
  return host.trim();
}

export function credentialPath(env = process.env) {
  return env.TARGET_GOOGLE_APPLICATION_CREDENTIALS || env.GOOGLE_APPLICATION_CREDENTIALS || '';
}

/**
 * @returns {string} a refusal message, or '' when the invocation may continue.
 */
export function liveTargetError({ apply, allowProd, project, host, credPath }) {
  if (project === 'tranyx-uat') {
    return 'Refusing tranyx-uat. This tooling does not target UAT.';
  }
  if (!host && !project) {
    return 'Pass --project <id>, or set FIRESTORE_EMULATOR_HOST for an emulator run.';
  }
  if (project === 'tranyx-app' && !allowProd) {
    return 'Refusing tranyx-app without --allow-prod.';
  }
  if (apply && !host) {
    if (project !== 'tranyx-app' || !allowProd) {
      return 'Live --apply requires --project tranyx-app --allow-prod. Set FIRESTORE_EMULATOR_HOST to apply on the emulator.';
    }
    if (!credPath) {
      return 'Live --apply requires GOOGLE_APPLICATION_CREDENTIALS or TARGET_GOOGLE_APPLICATION_CREDENTIALS (service account JSON path).';
    }
  }
  if (!host && !credPath) {
    return 'A live dry run requires GOOGLE_APPLICATION_CREDENTIALS or TARGET_GOOGLE_APPLICATION_CREDENTIALS (service account JSON path).';
  }
  return '';
}

export function refuseLive(argv, env = process.env) {
  const args = parseLiveArgs(argv);
  const message = liveTargetError({
    ...args,
    host: emulatorHost(env),
    credPath: credentialPath(env),
  });
  return { ...args, host: emulatorHost(env), credPath: credentialPath(env), message };
}

export function logWrite(entry) {
  console.log(JSON.stringify({ ts: new Date().toISOString(), ...entry }));
}
