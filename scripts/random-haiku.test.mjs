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
            assert.equal(button.disabled, true);
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
    return { fetched, status, host, button, window };
}

test("empty list reports no published writing and does not fetch", async () => {
    const { fetched, status, host, button } = await readHaiku([]);
    assert.deepEqual(fetched, []);
    assert.equal(status.hidden, false);
    assert.equal(status.textContent, `No published ${kind === "story" ? "stories" : "haiku"} are available yet.`);
    assert.deepEqual(host.children, []);
    assert.equal(button.hidden, false);
    assert.equal(button.disabled, false);
    await button.click();
    assert.match(status.textContent, /No published/);
    assert.deepEqual(fetched, []);
});

test("one target imports the authored article and clears loading without navigation", async () => {
    for (const random of [0, 0.5, 0.999999]) {
        const { fetched, status, host } = await readHaiku(["/preview/haiku/only"], random);
        assert.deepEqual(fetched, ["https://pelgish.ink/preview/haiku/only"]);
        assert.deepEqual(host.children, [{
            title: "Authored title",
            body: kind === "story" ? "<h1>Authored heading</h1><p>First paragraph.</p><p>Second paragraph.</p>" :
                "<p>First line<br>Second line</p>",
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
        assert.equal(status.textContent, `Unable to load a ${kind}. Please try the Get a new ${kind} button again.`);
        assert.deepEqual(host.children, []);
    }
});

test("new writing button fetches again in place and ignores overlapping requests", async () => {
    const options = {};
    const { fetched, status, host, button, window } = await readHaiku(["/haiku/only"], 0, options);
    const previous = host.children[0];
    let release;
    options.beforeResponse = () => new Promise(resolve => { release = resolve; });
    const pending = button.click();
    assert.equal(button.disabled, true);
    assert.equal(button.hidden, false);
    assert.match(status.textContent, /Loading/);
    await button.click();
    assert.equal(fetched.length, 2, "Initial fetch and one click, not the overlapping click");
    assert.equal(host.children[0], previous, "Keep current writing until the next is ready");
    release();
    await pending;
    assert.equal(button.disabled, false);
    assert.equal(status.hidden, true);
    assert.notEqual(host.children[0], previous);
    assert.equal(window.location.href, readerURL);
});

test("failed click preserves the latest writing and the button retries successfully", async () => {
    const options = {};
    const { fetched, status, host, button } = await readHaiku(["/haiku/only"], 0, options);
    const previous = host.children[0];
    for (const failure of [{ networkFailure: true }, { httpError: 404 }, { httpError: 500 },
        { missingArticle: true }, { missingBody: true }]) {
        Object.assign(options, failure);
        await button.click();
        assert.equal(host.children[0], previous);
        assert.equal(status.hidden, false);
        assert.match(status.textContent, /Unable to load/);
        assert.equal(button.disabled, false);
        for (const key of Object.keys(failure)) delete options[key];
    }
    await button.click();
    assert.equal(fetched.length, 7);
    assert.equal(status.hidden, true);
    assert.equal(button.disabled, false);
    assert.notEqual(host.children[0], previous);
});

test("initial network failure can be retried with the new writing button", async () => {
    const options = { networkFailure: true };
    const { status, host, button } = await readHaiku(["/haiku/only"], 0, options);
    assert.equal(button.disabled, false);
    options.networkFailure = false;
    await button.click();
    assert.equal(host.children.length, 1);
    assert.equal(status.hidden, true);
});

test("self and external targets fail without fetching or navigating", async () => {
    for (const target of [readerURL, "https://elsewhere.example/haiku", "//elsewhere.example/story",
        "javascript:alert(1)", "file:///story"]) {
        const { fetched, status } = await readHaiku([target]);
        assert.deepEqual(fetched, []);
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
