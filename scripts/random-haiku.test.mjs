/* Exercise the browser entry point with deterministic choices and DOM/network boundaries. */
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test as nodeTest } from "node:test";
import assert from "node:assert/strict";

const script = readFileSync(new URL("../assets/js/random-haiku.js", import.meta.url), "utf8");
// Run the same lifecycle/failure contract for legacy haiku markup and story markup.
for (const kind of ["haiku", "story"]) {
const test = (name, fn) => nodeTest(`${kind}: ${name}`, fn);
const readerURL = `https://pelgish.ink/preview/${kind}/random`;

// Navigation and shell mutation fail immediately; only the content host is writable.
async function readHaiku(targets, random = 0, options = {}) {
    const fetched = [];
    const status = { textContent: "", hidden: true };
    const link = { hidden: true };
    const host = {
        dataset: kind === "story" ? { kind } : {},
        children: [],
        replaceChildren(...children) { this.children = children; },
    };
    const button = {
        hidden: true,
        disabled: false,
        addEventListener(event, handler) {
            assert.equal(event, "click");
            this.click = handler;
        },
    };
    const article = {
        title: "Authored title",
        body: kind === "story" ? "<h1>Authored heading</h1><p>First paragraph.</p><p>Second paragraph.</p>" :
            "<p>First line<br>Second line</p>",
        querySelector(selector) {
            assert.equal(selector, ".writing-body");
            return options.missingBody ? null : { innerHTML: this.body };
        },
    };
    const location = Object.freeze({
        href: readerURL,
        origin: new URL(readerURL).origin,
        pathname: new URL(readerURL).pathname,
    });
    const window = Object.freeze({ location });
    await runInNewContext(script, {
        document: {
            getElementById(id) {
                return {
                    [`${kind}-targets`]: { textContent: options.rawTargets ?? JSON.stringify(targets) },
                    [`${kind}-content`]: host,
                    [`${kind}-status`]: status,
                    [`${kind}-another`]: button,
                    [`${kind}-link`]: link,
                }[id];
            },
            importNode(node, deep) {
                assert.equal(node, article);
                assert.equal(deep, true);
                return { title: node.title, body: node.body };
            },
        },
        Math: { floor: Math.floor, random: () => typeof random === "function" ? random() : random },
        window,
        URL,
        async fetch(url, init) {
            fetched.push(url);
            assert.equal(init.mode, "same-origin");
            assert.equal(init.redirect, "error");
            assert.equal(button.disabled, true);
            assert.equal(status.hidden, true);
            assert.equal(status.textContent, "");
            if (fetched.length === 1) {
                assert.deepEqual(host.children, [], "Initial writing stays blank until success");
                assert.equal(link.hidden, true);
            }
            if (options.beforeResponse) await options.beforeResponse();
            if (options.networkFailure) throw new Error("Offline");
            return {
                ok: !options.httpError,
                status: options.httpError || 200,
                text: async () => "<html>Generated page fixture</html>",
            };
        },
        DOMParser: class {
            parseFromString(html, type) {
                assert.equal(html, "<html>Generated page fixture</html>");
                assert.equal(type, "text/html");
                return {
                    querySelector(selector) {
                        assert.equal(selector, `article.writing.${kind === "story" ? "prose" : "poetry"}`);
                        return options.missingArticle ? null : article;
                    },
                };
            }
        },
    });
    assert.equal(window.location.href, readerURL);
    return { fetched, status, host, button, link, window };
}

test("empty list reports no published writing and does not fetch", async () => {
    const { fetched, status, host, button, link } = await readHaiku([]);
    assert.deepEqual(fetched, []);
    assert.equal(status.hidden, false);
    assert.equal(status.textContent, `No published ${kind === "story" ? "stories" : "haiku"} are available yet.`);
    assert.deepEqual(host.children, []);
    assert.equal(button.hidden, false);
    assert.equal(button.disabled, false);
    assert.equal(link.hidden, true);
    assert.equal(link.href, undefined);
    await button.click();
    assert.equal(status.hidden, false);
    assert.match(status.textContent, /No published/);
    assert.deepEqual(fetched, []);
});

test("one target imports the authored article with hidden status and no navigation", async () => {
    for (const random of [0, 0.5, 0.999999]) {
        const { fetched, status, host, button, link } = await readHaiku([`/preview/${kind}/only`], random);
        assert.deepEqual(fetched, [`https://pelgish.ink/preview/${kind}/only`]);
        assert.equal(link.href, fetched[0]);
        assert.equal(link.hidden, false);
        assert.deepEqual(host.children, [{
            title: "Authored title",
            body: kind === "story" ? "<h1>Authored heading</h1><p>First paragraph.</p><p>Second paragraph.</p>" :
                "<p>First line<br>Second line</p>",
        }]);
        assert.equal(status.hidden, true);
        assert.equal(status.textContent, "");
        await button.click();
        assert.deepEqual(fetched, [link.href, link.href], "A one-item bag can repeat");
    }
});

test("shuffled bags cover each target exactly once per cycle and update the matching link", async () => {
    const targets = [`/preview/${kind}/first`, "/preview/elsewhere/override", `/preview/${kind}/nested/last`];
    const expected = targets.map(target => `https://pelgish.ink${target}`);
    for (const random of [0, 0.5, 0.999999]) {
        const { fetched, button, link } = await readHaiku(targets, random);
        assert.equal(link.href, fetched[0], "Initial display includes its permalink");
        for (let i = 1; i < targets.length * 4; i++) {
            await button.click();
            assert.equal(link.href, fetched[i], "Every successful display updates its permalink");
            assert.equal(link.hidden, false);
            assert.notEqual(fetched[i], fetched[i - 1], "No immediate repeat, even at cycle boundaries");
        }
        for (let start = 0; start < fetched.length; start += targets.length) {
            assert.deepEqual(fetched.slice(start, start + targets.length).sort(), [...expected].sort());
        }
    }
});

test("Fisher-Yates uses deterministic swaps and corrects a repeated boundary item", async () => {
    const targets = [`/preview/${kind}/first`, "/preview/elsewhere/override", `/preview/${kind}/last`];
    const values = [0, 0, 0.5, 0];
    let draws = 0;
    const { fetched, button } = await readHaiku(targets, () => {
        assert.ok(draws < values.length, "Randomness is used only when refilling");
        return values[draws++];
    });
    for (let i = 1; i < 6; i++) await button.click();
    assert.equal(draws, 4);
    assert.deepEqual(fetched, [0, 2, 1, 2, 0, 1].map(i => `https://pelgish.ink${targets[i]}`));
});

test("two-item cycles never immediately repeat at a refill", async () => {
    let draws = 0;
    const { fetched, button } = await readHaiku([`/${kind}/a`, `/${kind}/b`], () => draws++ % 2 ? 0.999999 : 0);
    for (let i = 1; i < 8; i++) await button.click();
    assert.deepEqual(fetched, Array.from({ length: 8 }, (_, i) => `https://pelgish.ink/${kind}/${i % 2 ? "b" : "a"}`));
});

test("serialized URLs preserve baseurl, encoding and special characters", async () => {
    const target = "/preview/elsewhere/a%20b?x=one&y=%22two%22";
    const { fetched, link } = await readHaiku([target]);
    assert.deepEqual(fetched, [`https://pelgish.ink${target}`]);
    assert.equal(link.href, fetched[0]);
});

test("HTTP errors, network failure and unexpected HTML visibly fail", async () => {
    for (const options of [{ httpError: 404 }, { httpError: 500 }, { networkFailure: true },
        { missingArticle: true }, { missingBody: true }]) {
        const { status, host, link } = await readHaiku([`/${kind}/only`], 0, options);
        assert.equal(status.hidden, false);
        assert.equal(status.textContent, `Unable to load a ${kind}. Please try the Get a new ${kind} button again.`);
        assert.deepEqual(host.children, []);
        assert.equal(link.hidden, true);
        assert.equal(link.href, undefined);
    }
});

test("new writing button fetches again in place and ignores overlapping requests", async () => {
    const options = {};
    const { fetched, status, host, button, link, window } = await readHaiku([`/${kind}/first`, `/${kind}/second`], 0, options);
    const previous = host.children[0];
    const previousLink = link.href;
    let release;
    options.beforeResponse = () => new Promise(resolve => { release = resolve; });
    const pending = button.click();
    assert.equal(button.disabled, true);
    assert.equal(button.hidden, false);
    assert.equal(status.hidden, true);
    assert.equal(status.textContent, "");
    await button.click();
    assert.equal(fetched.length, 2, "Initial fetch and one click, not the overlapping click");
    assert.equal(host.children[0], previous, "Keep current writing until the next is ready");
    assert.equal(link.href, previousLink, "Keep the matching link while loading");
    release();
    await pending;
    assert.equal(button.disabled, false);
    assert.equal(status.hidden, true);
    assert.equal(status.textContent, "");
    assert.notEqual(host.children[0], previous);
    assert.notEqual(link.href, previousLink);
    assert.equal(link.href, fetched[1]);
    assert.equal(window.location.href, readerURL);
});

test("failed click preserves the latest writing and the button retries successfully", async () => {
    const options = {};
    const targets = [`/${kind}/first`, "/preview/elsewhere/override", `/${kind}/last`];
    let draws = 0;
    const { fetched, status, host, button, link } = await readHaiku(targets, () => { draws++; return 0; }, options);
    const previous = host.children[0];
    const previousLink = link.href;
    for (const failure of [{ networkFailure: true }, { httpError: 404 }, { httpError: 500 },
        { missingArticle: true }, { missingBody: true }]) {
        Object.assign(options, failure);
        await button.click();
        assert.equal(host.children[0], previous);
        assert.equal(link.href, previousLink);
        assert.equal(link.hidden, false);
        assert.equal(status.hidden, false);
        assert.match(status.textContent, /Unable to load/);
        assert.equal(button.disabled, false);
        for (const key of Object.keys(failure)) delete options[key];
    }
    await button.click();
    assert.equal(fetched.length, 7);
    assert.deepEqual(fetched.slice(1), Array(6).fill(`https://pelgish.ink${targets[2]}`),
        "Failures retry the same unconsumed selection");
    assert.equal(draws, 2, "Failures must not refill or reshuffle the bag");
    assert.equal(link.href, fetched[6]);
    assert.equal(status.hidden, true);
    assert.equal(button.disabled, false);
    assert.notEqual(host.children[0], previous);
    await button.click();
    assert.equal(fetched[7], `https://pelgish.ink${targets[1]}`, "The last unvisited item remains in the cycle");
});

test("initial network failure can be retried with the new writing button", async () => {
    const options = { networkFailure: true };
    const { fetched, status, host, button, link } = await readHaiku([`/${kind}/first`, `/${kind}/second`], 0, options);
    assert.equal(button.disabled, false);
    assert.equal(link.hidden, true);
    options.networkFailure = false;
    await button.click();
    assert.equal(host.children.length, 1);
    assert.equal(status.hidden, true);
    assert.equal(fetched[1], fetched[0], "An initial failure must not consume the candidate");
    assert.equal(link.href, fetched[1]);
    assert.equal(link.hidden, false);
});

test("self and external targets fail without fetching or navigating", async () => {
    for (const target of [readerURL, "https://elsewhere.example/haiku", "//elsewhere.example/story",
        "javascript:alert(1)", "file:///story"]) {
        const { fetched, status } = await readHaiku([target]);
        assert.deepEqual(fetched, []);
        assert.equal(status.hidden, false);
        assert.match(status.textContent, /Unable to load/);
    }

});

test("invalid target JSON or non-list input reports a list error without fetching", async () => {
    for (const rawTargets of ["{broken", "null", "{}", '"not a list"']) {
        const { fetched, status, button } = await readHaiku([], 0, { rawTargets });
        assert.deepEqual(fetched, []);
        assert.equal(status.hidden, false);
        assert.equal(status.textContent,
            `Unable to read the ${kind} list. Please reload the page to try again.`);
        assert.equal(button.hidden, true);
    }
});
}

nodeTest("both readers pair initially hidden native controls above and outside the writing", () => {
    for (const kind of ["haiku", "story"]) {
        const markup = readFileSync(new URL(`../content/${kind}/_random.md`, import.meta.url), "utf8");
        const anchor = markup.match(new RegExp(`<a id="${kind}-link" class="icon-control hero-control" hidden>([\\s\\S]*?)</a>`));
        assert.ok(anchor, `${kind} uses the shared responsive, keyboard-focusable control`);
        assert.match(anchor[1], /<span class="control-icon icon-link icon-wiggle" aria-hidden="true"><\/span>/);
        assert.match(anchor[1], new RegExp(`<span>Link to this ${kind}</span>`));
        assert.doesNotMatch(anchor[0], /icon-spin|target=|download|onclick|role=/);
        assert.ok(markup.indexOf(anchor[0]) < markup.indexOf(`<p id="${kind}-status"`));
        assert.ok(markup.indexOf(anchor[0]) < markup.indexOf(`<div id="${kind}-content"`));
        const row = markup.match(/<div class="random-reader-controls">([\s\S]*?)<\/div>/);
        assert.ok(row);
        assert.ok(row[1].includes(anchor[0]));
        assert.match(row[1], new RegExp(`<button id="${kind}-another" class="icon-control hero-control" type="button" aria-label="Get a new ${kind}" title="Get a new ${kind}" hidden>`));
        assert.ok(markup.indexOf(row[0]) + row[0].length < markup.indexOf(`<div id="${kind}-content"`));
        for (const id of [`${kind}-link`, `${kind}-another`, `${kind}-content`]) {
            assert.equal(markup.match(new RegExp(`id="${id}"`, "g"))?.length, 1);
        }
        assert.match(markup, /<script src="\{\{ '\/assets\/js\/random-haiku.js' \| relative_url \}\}" defer><\/script>/);
    }
});

nodeTest("home navigation places the unchanged Short Stories anchor before Haikus", () => {
    const markup = readFileSync(new URL("../index.md", import.meta.url), "utf8");
    const stories = [
        `    <a class="icon-control" href="{{ '/story' | relative_url }}" aria-label="Short Stories" title="Read short stories">`,
        '        <span class="control-icon icon-shortstory" aria-hidden="true"></span>',
        '        <span>Short Stories</span>',
        '    </a>',
    ].join("\n");
    const haikus = [
        `    <a class="icon-control" href="{{ '/haiku' | relative_url }}" aria-label="Haikus" title="Read haikus">`,
        '        <span class="control-icon icon-haiku" aria-hidden="true"></span>',
        '        <span>Haikus</span>',
        '    </a>',
    ].join("\n");
    assert.ok(markup.includes(stories));
    assert.ok(markup.includes(haikus));
    assert.ok(markup.indexOf(stories) < markup.indexOf(haikus));
});
