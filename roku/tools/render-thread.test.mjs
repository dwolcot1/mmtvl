// Objects Roku won't create on the render thread. A component that isn't a Task runs its code there: CreateObject
// returns invalid (the console says "creating MAIN|TASK-only component failed on RENDER thread") and the first call
// on it stops the app in the debugger. Build 2 (step 15's first device run): MainScene's and GuideScreen's
// roFileSystem froze the app on Settings. Run with `npm run test:tools`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
// roFileSystem: seen on the device (build 2). roUrlTransfer and the sockets: Roku's thread rules (Task or main only).
const taskOnly = ['roFileSystem', 'roUrlTransfer', 'roStreamSocket', 'roDataGramSocket'];

function filesUnder(directory, extension) {
    const found = [];
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const path = join(directory, entry.name);
        if (entry.isDirectory()) found.push(...filesUnder(path, extension));
        else if (entry.name.endsWith(extension)) found.push(path);
    }
    return found;
}

// Every component's own scripts (pkg:/components/…), and whether the component is a Task.
function components() {
    return filesUnder(join(root, 'components'), '.xml').map((xml) => {
        const text = readFileSync(xml, 'utf8');
        const isTask = /<component\b[^>]*\bextends="Task"/.test(text);
        const scripts = [...text.matchAll(/<script\b[^>]*\buri="pkg:\/(components\/[^"]+\.bs)"/g)].map((m) => join(root, m[1]));
        // bsc pairs a component with the .bs of the same name beside its XML, without a <script> tag.
        const own = xml.replace(/\.xml$/, '.bs');
        if (existsSync(own) && !scripts.includes(own)) scripts.push(own);
        return { xml, isTask, scripts };
    });
}

// Code only: comments (') and strings are left out, so a note that names an object doesn't count.
function codeOf(line) {
    let out = '';
    let inString = false;
    for (const ch of line) {
        if (ch === '"') inString = !inString;
        else if (!inString && ch === "'") break;
        out += inString && ch !== '"' ? '' : ch;
    }
    return out;
}

function creations(path) {
    const hits = [];
    readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
        for (const name of taskOnly) {
            if (new RegExp(`CreateObject\\(\\s*"${name}"`, 'i').test(line) && /CreateObject\(/i.test(codeOf(line))) {
                hits.push(`${relative(root, path)}:${index + 1} ${name}`);
            }
        }
    });
    return hits;
}

test('the scan finds the components and both kinds', () => {
    const all = components();
    assert.ok(all.some((c) => c.isTask), 'some Task');
    assert.ok(all.some((c) => !c.isTask && c.scripts.some((s) => s.endsWith('MainScene.bs'))), 'MainScene, not a Task');
});

test('the check catches a render-thread roFileSystem', () => {
    assert.equal(codeOf('    m.fs = CreateObject("roFileSystem") \' note'), '    m.fs = CreateObject("") ');
    assert.equal(codeOf("    ' m.fs = CreateObject(\"roFileSystem\")"), '    ');
});

test('no render-thread component creates a Task-only object', () => {
    const shared = new Set(components().filter((c) => c.isTask).flatMap((c) => c.scripts));
    const hits = components()
        .filter((c) => !c.isTask)
        .flatMap((c) => c.scripts)
        // A script a Task also includes (ProbeKit) is checked by hand: its file calls run in the Task.
        .filter((script) => !shared.has(script))
        .flatMap(creations);
    assert.deepEqual([...new Set(hits)], []);
});
