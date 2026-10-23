/* Exercise appearance initialization and updates without browser dependencies. */
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test } from "node:test";
import assert from "node:assert/strict";

const script = readFileSync(new URL("../assets/js/appearance.js", import.meta.url), "utf8");

// Supply only the DOM/storage APIs the toggle needs; replacing markup must fail.
function appearance({ dark = false, hint, saved, storageError } = {}) {
    const root = { dataset: hint ? { appearance: hint } : {} };
    const handlers = {};
    const writes = [];
    const icons = Object.freeze(["moon", "sun"]);
    const button = {
        hidden: true,
        children: icons,
        setAttribute(name, value) { this[name] = value; },
        addEventListener(name, callback) { handlers[name] = callback; },
        set innerHTML(value) { assert.fail("Toggle must not replace its icons"); },
        set textContent(value) { assert.fail("Toggle must not replace its icons"); },
    };
    const system = {
        matches: dark,
        addEventListener(name, callback) {
            assert.equal(name, "change");
            handlers.system = callback;
        },
    };
    runInNewContext(script, {
        DOMException,
        document: {
            documentElement: root,
            getElementById(id) {
                assert.equal(id, "appearance-toggle");
                return button;
            },
            addEventListener(name, callback) { handlers[name] = callback; },
        },
        window: {
            matchMedia: () => system,
            localStorage: {
                getItem() {
                    if (storageError === "SecurityError") throw new DOMException("Blocked", storageError);
                    return saved;
                },
                setItem(key, value) {
                    if (storageError) throw new DOMException("Unavailable", storageError);
                    writes.push([key, value]);
                },
            },
        },
    });
    return { root, button, system, handlers, writes, icons };
}

// Check both the root mode (which selects the CSS icon) and next-action labels.
function checkMode(state, mode) {
    const next = mode === "light" ? "dark" : "light";
    const label = `Switch to ${next} mode (currently ${mode} mode)`;
    assert.equal(state.root.dataset.appearance, mode);
    assert.equal(state.button["aria-label"], label);
    assert.equal(state.button.title, label);
    assert.equal(state.button.children, state.icons);
}

test("system preference initializes before enhancement and follows later changes", () => {
    for (const dark of [false, true]) {
        const state = appearance({ dark });
        checkMode(state, dark ? "dark" : "light");
        assert.equal(state.button.hidden, true);
        state.handlers.DOMContentLoaded();
        assert.equal(state.button.hidden, false);
        state.system.matches = !dark;
        state.handlers.system();
        checkMode(state, dark ? "light" : "dark");
    }
});

test("saved choices beat page hints; invalid saved choices do not", () => {
    for (const mode of ["light", "dark"]) {
        checkMode(appearance({ dark: mode !== "dark", hint: mode === "dark" ? "light" : "dark", saved: mode }), mode);
        checkMode(appearance({ hint: mode, saved: "invalid" }), mode);
    }
});

test("clicks persist both modes, keep icon markup, and override system changes", () => {
    const state = appearance();
    state.handlers.DOMContentLoaded();
    state.handlers.click();
    checkMode(state, "dark");
    state.handlers.system();
    checkMode(state, "dark");
    state.handlers.click();
    checkMode(state, "light");
    assert.deepEqual(state.writes, [["pelgish-appearance", "dark"], ["pelgish-appearance", "light"]]);
});

test("blocked and full storage leave the toggle usable", () => {
    for (const storageError of ["SecurityError", "QuotaExceededError"]) {
        const state = appearance({ dark: true, storageError });
        state.handlers.DOMContentLoaded();
        state.handlers.click();
        checkMode(state, "light");
        assert.equal(state.button.hidden, false);
    }
});

test("icon CSS uses palette colors, alpha masks, borderless targets and keyboard outlines", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    const controls = css.match(/\.icon-control,\s*[\s\S]*?\{([^}]+)\}/)[1];
    for (const declaration of ["background: transparent", "border: 0", "box-shadow: none",
        "min-height: 44px", "min-width: 44px", "flex-shrink: 0", "color: var(--foreground)"]) {
        assert.ok(controls.includes(declaration), declaration);
    }
    assert.match(css, /\.icon-control:hover\s*\{\s*color: var\(--accent-link\)/);
    assert.match(css, /:focus-visible\s*\{[^}]*outline: 2px solid currentColor/);
    assert.match(css, /\.icon-control:not\(\[hidden\]\)\s*\{[^}]*display: inline-flex/);
    assert.match(css, /\.control-icon\s*\{[^}]*background: currentColor;[^}]*mask: var\(--icon-image\) center \/ contain no-repeat/);
    for (const icon of ["haiku", "shortstory", "moon", "sun"]) {
        assert.ok(css.includes(`url("../images/icon_${icon}.png")`));
    }
    assert.match(css, /\.appearance-sun,\s*:root\[data-appearance="dark"\] \.appearance-moon\s*\{\s*display: none/);
    assert.match(css, /:root\[data-appearance="dark"\] \.appearance-sun\s*\{\s*display: inline-block/);
});

test("home copyright uses a growing viewport layout, not a fixed overlay", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /\.home-page\s*\{\s*display: flex;\s*flex-direction: column;\s*min-height: 100svh/);
    assert.match(css, /\.home-page main\s*\{[^}]*flex: 1 0 auto;[^}]*flex-direction: column;[^}]*margin-bottom: 0/);
    assert.match(css, /\.home-copyright\s*\{\s*font-size: 0.8rem;\s*margin-top: auto;\s*padding-bottom: calc\(1.5rem \+ env\(safe-area-inset-bottom, 0px\)\);\s*\}/);
    assert.match(css, /\.home-copyright p\s*\{\s*margin: 0;\s*\}/);
    assert.doesNotMatch(css, /(?:^|[;{])\s*(?:position:\s*fixed|height:\s*100(?:s|d)?vh)/m);
});

test("home categories have large responsive icons; header aligns visual centers", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /\.home-controls\s*\{[^}]*flex-direction: column/);
    assert.match(css, /\.home-controls \.icon-control\s*\{[^}]*gap: 1rem;[^}]*max-width: 100%/);
    assert.match(css, /\.home-controls \.control-icon\s*\{\s*height: clamp\(80px, 24vw, 112px\);\s*width: clamp\(80px, 24vw, 112px\)/);
    assert.match(css, /\.site-header\s*\{\s*align-items: center;\s*display: flex/);
});
