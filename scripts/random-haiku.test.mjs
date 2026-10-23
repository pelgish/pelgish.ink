/* Exercise the browser entry point with deterministic choices and DOM/network boundaries. */
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test } from "node:test";
import assert from "node:assert/strict";

const script = readFileSync(new URL("../assets/js/random-haiku.js", import.meta.url), "utf8");
const readerURL = "https://pelgish.ink/preview/haiku/random";

// Navigation and shell mutation fail immediately; only the content host is writable.
async function readHaiku(targets, random = 0, options = {}) {
    const fetched = [];
    const status = { textContent: "", hidden: true };
    const host = { children: [], replaceChildren(...children) { this.children = children; } };
    const article = {
        title: "Authored title",
        body: "<p>First line<br>Second line</p>",
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
                    "haiku-targets": { textContent: JSON.stringify(targets) },
                    "haiku-content": host,
                    "haiku-status": status,
                }[id];
            },
            importNode(node, deep) {
                assert.equal(node, article);
                assert.equal(deep, true);
                return { title: node.title, body: node.body };
            },
        },
        Math: { floor: Math.floor, random: () => random },
        window,
        URL,
        async fetch(url, init) {
            fetched.push(url);
            assert.equal(init.mode, "same-origin");
            assert.equal(init.redirect, "error");
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
                        assert.equal(selector, "article.writing.poetry");
                        return options.missingArticle ? null : article;
                    },
                };
            }
        },
    });
    assert.equal(window.location.href, readerURL);
    return { fetched, status, host };
}

test("empty list reports no published haiku and does not fetch", async () => {
    const { fetched, status, host } = await readHaiku([]);
    assert.deepEqual(fetched, []);
    assert.equal(status.hidden, false);
    assert.match(status.textContent, /No published haiku/);
    assert.deepEqual(host.children, []);
});

test("one target imports the authored article and clears loading without navigation", async () => {
    for (const random of [0, 0.5, 0.999999]) {
        const { fetched, status, host } = await readHaiku(["/preview/haiku/only"], random);
        assert.deepEqual(fetched, ["https://pelgish.ink/preview/haiku/only"]);
        assert.deepEqual(host.children, [{
            title: "Authored title",
            body: "<p>First line<br>Second line</p>",
        }]);
        assert.equal(status.hidden, true);
        assert.equal(status.textContent, "");
    }
});

test("equal intervals fetch only the selected target, including permalink overrides", async () => {
    const targets = ["/preview/haiku/first", "/preview/elsewhere/override", "/preview/haiku/nested/last"];
    for (const [random, index] of [[0, 0], [0.32, 0], [1 / 3, 1], [0.65, 1], [2 / 3, 2], [0.999999, 2]]) {
        const { fetched } = await readHaiku(targets, random);
        assert.deepEqual(fetched, [`https://pelgish.ink${targets[index]}`]);
    }
});

test("serialized URLs preserve baseurl, encoding and special characters", async () => {
    const target = "/preview/elsewhere/a%20b?x=one&y=%22two%22";
    assert.deepEqual((await readHaiku([target])).fetched, [`https://pelgish.ink${target}`]);
});

test("HTTP errors, network failure and unexpected HTML visibly fail", async () => {
    for (const options of [{ httpError: 404 }, { httpError: 500 }, { networkFailure: true },
        { missingArticle: true }, { missingBody: true }]) {
        const { status, host } = await readHaiku(["/haiku/only"], 0, options);
        assert.equal(status.hidden, false);
        assert.match(status.textContent, /Unable to load a haiku.*reload/);
        assert.deepEqual(host.children, []);
    }
});

test("self and external targets fail without fetching or navigating", async () => {
    for (const target of ["/preview/haiku/random", "https://elsewhere.example/haiku", "javascript:alert(1)"]) {
        const { fetched, status } = await readHaiku([target]);
        assert.deepEqual(fetched, []);
        assert.match(status.textContent, /Unable to load/);
    }
});
