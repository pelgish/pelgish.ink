/* Exercise appearance initialization and updates without browser dependencies. */
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";
import { test } from "node:test";
import { inflateSync } from "node:zlib";
import assert from "node:assert/strict";

const script = readFileSync(new URL("../assets/js/appearance.js", import.meta.url), "utf8");

// Supply only the DOM/storage APIs the toggle needs; replacing markup must fail.
function appearance({ dark = false, hint, saved, storageError,
    href = "https://pelgish.ink/", canonical = "https://pelgish.ink/" } = {}) {
    const root = { dataset: hint ? { appearance: hint } : {} };
    const handlers = {};
    const writes = [];
    const replacements = [];
    const location = new URL(href);
    const historyState = { reading: true };
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
        URL,
        document: {
            documentElement: root,
            querySelector(selector) {
                assert.equal(selector, 'link[rel="canonical"]');
                return canonical ? { href: canonical } : null;
            },
            getElementById(id) {
                assert.equal(id, "appearance-toggle");
                return button;
            },
            addEventListener(name, callback) { handlers[name] = callback; },
        },
        window: {
            location,
            history: {
                state: historyState,
                replaceState(state, title, url) {
                    assert.equal(state, historyState);
                    assert.equal(title, "");
                    replacements.push(url);
                },
            },
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
    return { root, button, system, handlers, writes, icons, replacements };
}

test("matching canonical removes only terminal slashes and preserves query, hash and baseurl", () => {
    for (const path of ["/haiku", "/story", "/haiku/random", "/story/random", "/haiku/a-verse", "/preview/haiku"]) {
        for (const suffix of ["/", "///"]) {
            const state = appearance({
                href: `https://pelgish.ink${path}${suffix}?q=a%20b#verse`,
                canonical: `https://pelgish.ink${path}`,
            });
            state.handlers.DOMContentLoaded();
            assert.deepEqual(state.replacements, [`${path}?q=a%20b#verse`]);
            checkMode(state, "light");
        }
    }
});

test("normalization leaves root, clean paths, extensions and unrelated canonicals alone", () => {
    for (const [path, canonical] of [
        ["/", "https://pelgish.ink/"],
        ["/preview/", "https://pelgish.ink/preview/"],
        ["/haiku", "https://pelgish.ink/haiku"],
        ["/haiku.html", "https://pelgish.ink/haiku"],
        ["/haiku.html/", "https://pelgish.ink/haiku"],
        ["/haiku/", "https://other.example/haiku"],
        ["/haiku/", "https://pelgish.ink/elsewhere"],
        ["/haiku/", null],
    ]) {
        const state = appearance({ href: `https://pelgish.ink${path}`, canonical });
        state.handlers.DOMContentLoaded();
        assert.deepEqual(state.replacements, []);
    }
});

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
    assert.match(css, /\.icon-control:hover,\s*\.icon-control:focus,\s*\.icon-control:active\s*\{\s*color: var\(--accent-link\)/);
    assert.match(css, /:focus-visible\s*\{[^}]*outline: 2px solid currentColor/);
    assert.match(css, /\.icon-control:not\(\[hidden\]\)\s*\{[^}]*display: inline-flex/);
    const glyph = css.match(/\.control-icon\s*\{([^}]+)\}/)[1];
    assert.ok(glyph.includes("background: currentColor"));
    assert.ok(glyph.includes("mask-mode: alpha"));
    for (const prefix of ["-webkit-", ""]) {
        for (const [property, value] of [["position", "center"], ["size", "contain"], ["repeat", "no-repeat"]]) {
            assert.ok(glyph.includes(`\n    ${prefix}mask-${property}: ${value};`));
        }
    }
    for (const icon of ["haiku", "shortstory", "moon", "sun", "arrowcircle", "link"]) {
        const selector = ["moon", "sun"].includes(icon) ? `appearance-${icon}` : `icon-${icon}`;
        const rule = css.match(new RegExp(`\\.${selector}(?:,\\s*\\.icon-sun)?\\s*\\{([^}]+)\\}`))[1];
        for (const prefix of ["-webkit-", ""]) {
            assert.ok(rule.includes(`\n    ${prefix}mask-image: url("../images/icon_${icon}.png");`));
        }
    }
    assert.match(css, /\.appearance-sun,\s*\.icon-sun\s*\{[^}]*mask-image: url\("\.\.\/images\/icon_sun\.png"\)/);
    assert.match(css, /\.appearance-sun,\s*:root\[data-appearance="dark"\] \.appearance-moon\s*\{\s*display: none/);
    assert.match(css, /:root\[data-appearance="dark"\] \.appearance-sun\s*\{\s*display: inline-block/);
});

test("ordinary links default to theme accent in every state without a class or underline", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /(?:^|\n)a\s*\{\s*color: var\(--accent-link\);\s*text-decoration: none;\s*\}/);
    // A bare type selector covers normal/visited/hover/focus/active equally.
    // No state or opt-in class may raise specificity above shared controls.
    assert.doesNotMatch(css, /(?:^|[,\s])a[.:]/m);
    assert.doesNotMatch(css, /\.accent-link\b|!important/);
    assert.match(css, /:focus-visible\s*\{\s*outline: 2px solid currentColor;\s*outline-offset: 4px;\s*\}/);
    assert.match(css, /:root\[data-color-scheme="grapevine"\]\s*\{[^}]*--accent-link: #755E70;[^}]*--dark-accent-link: #A28F9D;/);
    assert.match(css, /:root\[data-appearance="dark"\]\s*\{[^}]*--accent-link: var\(--dark-accent-link\);/);
    assert.match(css, /@media \(prefers-color-scheme: dark\)\s*\{[^}]*--accent-link: var\(--dark-accent-link\);/);
});

test("generated stylesheet URLs bypass prior-build caches at root and preview baseurls", () => {
    const root = fileURLToPath(new URL("../", import.meta.url));
    // Build the actual shared shell, not a regex approximation of Liquid output.
    const results = JSON.parse(execFileSync(`${root}scripts/bundle.sh`, ["exec", "ruby",
        "-rjekyll", "-rtmpdir", "-rfileutils", "-rjson", "-e", `
        root = ARGV.fetch(0)
        results = []
        Dir.mktmpdir("pelgish-appearance-") do |source|
            %w[_config.yml _plugins _layouts assets].each do |path|
                FileUtils.cp_r(File.join(root, path), source)
            end
            File.write(File.join(source, "index.md"), "---\\n---\\n[Ordinary link](/legal)\\n")
            ["", "/preview"].each do |baseurl|
                [Time.utc(2026, 10, 25, 12), Time.utc(2026, 10, 25, 13)].each do |time|
                    config = Jekyll.configuration("source" => source,
                        "destination" => File.join(source, "_site"),
                        "baseurl" => baseurl, "time" => time, "quiet" => true)
                    Jekyll::Site.new(config).process
                    html = File.read(File.join(source, "_site/index.html"))
                    href = html[/href="([^"]*\\/assets\\/css\\/style.css[^"]*)"/, 1]
                    results << { baseurl: baseurl, revision: time.to_i, href: href,
                        css: File.read(File.join(source, "_site/assets/css/style.css"), encoding: "UTF-8") }
                end
            end
        end
        puts JSON.generate(results)
    `, root], { encoding: "utf8" }));
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    for (const { baseurl, revision, href, css: builtCss } of results) {
        assert.equal(href, `${baseurl}/assets/css/style.css?v=${revision}`);
        assert.equal(builtCss, css, "The versioned URL must still serve the original stylesheet");
    }
    assert.equal(new Set(results.map(({ href }) => href)).size, 4,
        "Each baseurl and subsequent build must have a distinct cache key");
});

test("button links and native buttons share foreground defaults and accent interactions", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    const base = /\.icon-control,\s*\.icon-control:visited,\s*\.icon-control:focus,\s*\.icon-control:active\s*\{[^}]*color: var\(--foreground\);/;
    const interaction = /\.icon-control:hover,\s*\.icon-control:focus,\s*\.icon-control:active\s*\{\s*color: var\(--accent-link\);\s*\}/;
    assert.match(css, base);
    assert.match(css, interaction);
    // Classes beat the bare a selector; equal-specificity visited/interaction
    // selectors resolve to the later interaction rule, even on visited links.
    assert.ok(css.search(interaction) > css.search(base));
    assert.match(css, /\.site-title,\s*\.site-title:visited,\s*\.site-title:hover,\s*\.site-title:focus\s*\{[^}]*color: var\(--heading\);/);
    const logoInteraction = /\.site-title:focus-visible,\s*\.site-title:active\s*\{\s*color: var\(--accent-link\);/;
    assert.match(css, logoInteraction);
    assert.ok(css.search(logoInteraction) > css.indexOf(".site-title,"));
});

test("supplied mask PNGs decode with visible strokes and transparent surrounding pixels", () => {
    for (const icon of ["haiku", "shortstory", "moon", "sun", "arrowcircle", "link", "logo"]) {
        const filename = icon === "logo" ? "logo.png" : `icon_${icon}.png`;
        const png = readFileSync(new URL(`../assets/images/${filename}`, import.meta.url));
        assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
        const width = png.readUInt32BE(16), height = png.readUInt32BE(20);
        assert.equal(width, icon === "logo" ? 2048 : 512);
        assert.equal(height, icon === "logo" ? 640 : 512);
        assert.equal(png[24], 8);
        assert.equal(png[25], 6, `${icon} requires RGBA transparency`);
        assert.equal(png[28], 0, "non-interlaced PNG");
        const chunks = [];
        for (let offset = 8; offset < png.length;) {
            const length = png.readUInt32BE(offset);
            if (png.toString("ascii", offset + 4, offset + 8) === "IDAT") {
                chunks.push(png.subarray(offset + 8, offset + 8 + length));
            }
            offset += length + 12;
        }
        const rows = inflateSync(Buffer.concat(chunks)), stride = width * 4 + 1;
        assert.equal(rows.length, stride * height);
        const alpha = new Uint8Array(width * height);
        // PNG row predictors use the same channel of neighboring RGBA pixels.
        for (let y = 0; y < height; y++) {
            const filter = rows[y * stride];
            for (let x = 0; x < width; x++) {
                const i = y * width + x, a = x ? alpha[i - 1] : 0;
                const b = y ? alpha[i - width] : 0, c = x && y ? alpha[i - width - 1] : 0;
                const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
                const paeth = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
                const predictor = [0, a, b, Math.floor((a + b) / 2), paeth][filter];
                assert.notEqual(predictor, undefined, "valid PNG filter");
                alpha[i] = (rows[y * stride + 1 + x * 4 + 3] + predictor) & 255;
            }
        }
        assert.ok(alpha.includes(0), `${icon} must not render as a solid rectangle`);
        assert.ok(alpha.includes(255), `${icon} must have visible strokes`);
    }
});

test("shared logo is an accessible home link with proportional theme-tinted artwork", () => {
    const markup = readFileSync(new URL("../_layouts/default.html", import.meta.url), "utf8");
    assert.match(markup, /<a class="site-title" href="\{\{ '\/' \| relative_url \}\}" aria-label="pelgish\.ink" title="pelgish\.ink">\s*<span class="site-logo" aria-hidden="true"><\/span>\s*<\/a>/);
    assert.match(markup, /<title>\{\{ page.title \| default: site.title \| escape \}\}<\/title>/);
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    const logo = css.match(/\.site-logo\s*\{([^}]+)\}/)[1];
    for (const declaration of ["background: currentColor",
        "display: block", "width: 100%", "mask-mode: alpha"]) {
        assert.ok(logo.includes(declaration), declaration);
    }
    for (const prefix of ["-webkit-", ""]) {
        for (const [property, value] of [["image", 'url("../images/logo.png")'],
            ["position", "center"], ["size", "contain"], ["repeat", "no-repeat"]]) {
            assert.ok(logo.includes(`\n    ${prefix}mask-${property}: ${value};`));
        }
    }
    assert.match(css, /\.site-title,\s*\.site-title:visited,\s*\.site-title:hover,\s*\.site-title:focus\s*\{[^}]*border: 0;[^}]*color: var\(--heading\);[^}]*max-width: calc\(100% - 44px - 0.75rem\);[^}]*min-height: 44px;[^}]*width: clamp\(144px, 40vw, 176px\)/);
    const hover = /@media \(hover: hover\) and \(pointer: fine\)\s*\{\s*\.site-title:hover\s*\{\s*color: var\(--accent-link\);/;
    const active = /\.site-title:focus-visible,\s*\.site-title:active\s*\{\s*color: var\(--accent-link\);/;
    assert.match(css, hover);
    assert.match(css, active);
    assert.ok(css.search(active) > css.search(hover), "Press feedback must follow hover/default rules");
    assert.doesNotMatch(logo, /transform|animation|transition/);
    assert.doesNotMatch(css, /h1, h2, h3, h4, h5, h6, \.site-title/);
});

test("empty logo reserves proportional height without aspect-ratio support", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    const logo = css.match(/\.site-logo\s*\{([^}]+)\}/)[1];
    // Empty flex children need a height source even when aspect-ratio is ignored.
    assert.match(logo, /(?:^|;)\s*height:\s*0\s*;/);
    assert.match(logo, /(?:^|;)\s*flex-shrink:\s*0\s*;/);
    const padding = Number(logo.match(/padding-bottom:\s*([\d.]+)%;/)?.[1]);
    const png = readFileSync(new URL("../assets/images/logo.png", import.meta.url));
    assert.equal(padding / 100, png.readUInt32BE(20) / png.readUInt32BE(16),
        "Percentage padding must preserve the original PNG proportions independently of aspect-ratio");
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
    assert.match(css, /\.home-controls\s*\{[^}]*display: grid;[^}]*grid-template-columns: repeat\(auto-fit, minmax\(min\(100%, 14rem\), 1fr\)\)/);
    assert.match(css, /\.home-controls \.icon-control,\s*\.hero-control\s*\{[^}]*flex-direction: column;[^}]*font-size: 1.3rem/);
    assert.match(css, /\.home-controls \.icon-control,\s*\.hero-control\s*\{[^}]*gap: 1rem;[^}]*max-width: 100%/);
    assert.match(css, /\.home-controls \.icon-control,\s*\.hero-control\s*\{[^}]*padding: 0.5rem;[^}]*text-align: center/);
    assert.match(css, /\.home-controls \.control-icon,\s*\.hero-control \.control-icon\s*\{\s*height: clamp\(64px, 20vw, 112px\);\s*width: clamp\(64px, 20vw, 112px\)/);
    assert.match(css, /\.home-controls \.control-icon,\s*\.hero-control \.control-icon,\s*\.haiku-heading \.control-icon,\s*\.story-heading \.control-icon\s*\{[^}]*transition: transform 1000ms cubic-bezier\(0.16, 1, 0.3, 1\)/);
    assert.match(css, /\.home-controls \.icon-control:active \.control-icon,\s*\.hero-control:active \.control-icon,\s*\.haiku-heading \.icon-control:active \.control-icon,\s*\.story-heading \.icon-control:active \.control-icon\s*\{\s*transform: scale\(1.15\)/);
    assert.match(css, /@media \(hover: hover\) and \(pointer: fine\) and \(prefers-reduced-motion: no-preference\)\s*\{\s*\.home-controls \.icon-control:hover \.control-icon,\s*\.hero-control:hover \.control-icon,\s*\.haiku-heading \.icon-control:hover \.control-icon,\s*\.story-heading \.icon-control:hover \.control-icon\s*\{\s*transform: scale\(1.15\)/);
    assert.match(css, /@media \(prefers-reduced-motion: reduce\)\s*\{[\s\S]*\.home-controls \.control-icon,\s*\.home-controls \.icon-control:active \.control-icon,\s*\.hero-control \.control-icon,\s*\.hero-control:active \.control-icon,\s*\.haiku-heading \.control-icon,\s*\.haiku-heading \.icon-control:active \.control-icon,\s*\.story-heading \.control-icon,\s*\.story-heading \.icon-control:active \.control-icon\s*\{\s*transform: none;\s*transition: none;\s*\}\s*\}\s*$/);
    assert.match(css, /\.site-header\s*\{\s*align-items: center;\s*display: flex/);
    assert.match(css, /\.hero-control\s*\{\s*margin: 1.5rem auto;\s*width: fit-content;/);
    assert.match(css, /\.hero-control:not\(\[hidden\]\)\s*\{\s*display: flex;/);
    assert.doesNotMatch(css, /#appearance-toggle[^{]*\{[^}]*(?:clamp|transition|scale)/);
});

test("haiku and story listings share compact heading geometry and accessible actions", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /\.haiku-heading,\s*\.story-heading\s*\{\s*align-items: center;\s*display: flex;\s*gap: 1rem;\s*justify-content: space-between;/);
    assert.match(css, /\.haiku-heading h1,\s*\.story-heading h1\s*\{\s*margin: 0;\s*min-width: 0;/);
    assert.match(css, /\.control-icon\s*\{[^}]*height: 2rem;\s*width: 2rem;/);
    assert.match(css, /\.icon-control:active\s*\{[^}]*min-height: 44px;\s*min-width: 44px;/);
    for (const [kind, title] of [["haiku", "Haikus"], ["story", "Short Stories"]]) {
        const markup = readFileSync(new URL(`../${kind}.md`, import.meta.url), "utf8");
        assert.match(markup, new RegExp(`<div class="${kind}-heading">\\s*<h1>${title}</h1>\\s*<a class="icon-control"[^>]*aria-label="Read a random ${kind}" title="Read a random ${kind}">`));
        assert.doesNotMatch(markup, /hero-control|<span>Read a random/);
    }
});

test("reusable spin runs only on hover or press with configurable speed/direction", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /\.icon-spin\s*\{\s*animation: icon-spin var\(--icon-spin-duration, 6s\) linear infinite;\s*animation-direction: var\(--icon-spin-direction, normal\);/);
    assert.match(css, /\.hero-control \.icon-spin\s*\{\s*height: clamp\(56px, 16vw, 96px\);\s*width: clamp\(56px, 16vw, 96px\);/);
    assert.match(css, /\.icon-spin\s*\{[^}]*animation-play-state: paused;/);
    assert.match(css, /\.icon-spin:active,\s*\.icon-control:active \.icon-spin\s*\{\s*animation-play-state: running;/);
    assert.match(css, /@media \(hover: hover\) and \(pointer: fine\)\s*\{\s*\.icon-spin:hover,\s*\.icon-control:hover \.icon-spin\s*\{\s*animation-play-state: running;/);
    assert.match(css, /@keyframes icon-spin\s*\{\s*from \{ rotate: 0turn; \}\s*to \{ rotate: 1turn; \}\s*\}/);
    assert.match(css, /@media \(prefers-reduced-motion: reduce\)\s*\{\s*\.icon-spin\s*\{\s*animation: none;\s*rotate: none;/);
    for (const path of ["../haiku.md", "../content/haiku/_random.md", "../story.md", "../content/story/_random.md"]) {
        const markup = readFileSync(new URL(path, import.meta.url), "utf8");
        assert.equal(markup.match(/class="control-icon icon-arrowcircle icon-spin"/g)?.length, 1);
    }
    for (const path of ["../index.md", "../_layouts/default.html"]) {
        assert.doesNotMatch(readFileSync(new URL(path, import.meta.url), "utf8"), /icon-spin/);
    }
    for (const kind of ["haiku", "story"]) {
        const reader = readFileSync(new URL(`../content/${kind}/_random.md`, import.meta.url), "utf8");
        assert.match(reader, new RegExp(`id="${kind}-another" class="icon-control hero-control"[\\s\\S]*class="control-icon icon-arrowcircle icon-spin"[\\s\\S]*Get a new ${kind}[\\s\\S]*id="${kind}-content"`));
    }
});

test("random readers pair compact controls with equal icons without changing other heroes", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /\.random-reader-controls\s*\{[^}]*align-items: flex-start;[^}]*display: flex;[^}]*flex-wrap: wrap;[^}]*gap: 1rem clamp\(1rem, 4vw, 2rem\);[^}]*justify-content: center;/);
    assert.match(css, /\.random-reader-controls \.hero-control\s*\{[^}]*font-size: 1rem;[^}]*gap: 0.5rem;[^}]*margin: 0;[^}]*width: clamp\(6rem, 34vw, 10rem\);/);
    assert.match(css, /\.random-reader-controls \.hero-control \.control-icon\s*\{\s*height: clamp\(40px, 12vw, 64px\);\s*width: clamp\(40px, 12vw, 64px\);\s*\}/);
    // At a 320px viewport, both targets plus their gap fit inside the body padding.
    const rem = 18, viewport = 320;
    const controlWidth = Math.min(10 * rem, Math.max(6 * rem, viewport * 0.34));
    const gap = Math.min(2 * rem, Math.max(rem, viewport * 0.04));
    assert.ok(controlWidth >= 44);
    assert.ok(2 * controlWidth + gap <= viewport - 2 * 1.25 * rem);
});

test("reusable wiggle has gentle configurable timing and opposite centered rotations", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    const utility = css.match(/\.icon-wiggle\s*\{([^}]+)\}/)?.[1];
    assert.ok(utility, "Shared wiggle utility must exist");
    assert.match(utility, /animation-duration: var\(--icon-wiggle-duration, 800ms\);/);
    assert.match(utility, /animation-iteration-count: infinite;/);
    assert.match(utility, /animation-name: none;/);
    assert.match(utility, /animation-timing-function: ease-in-out;/);
    assert.match(utility, /rotate: none;/);
    assert.match(utility, /transform-origin: center;/);
    assert.doesNotMatch(utility, /(?:^|[;{])\s*transform:/);
});

test("wiggle splits one symmetric easing curve across neutral without a loop-seam pause", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    const keyframes = css.match(/@keyframes icon-wiggle\s*\{([\s\S]*?)\n\}/)?.[1];
    assert.ok(keyframes, "Shared wiggle keyframes must exist");
    const frames = new Map();
    for (const [, offsets, body] of keyframes.matchAll(/([\d%,\s]+)\{([^}]+)\}/g)) {
        const declarations = Object.fromEntries(body.trim().split(";").filter(s => s.trim()).map(s =>
            s.trim().split(/\s*:\s*/)));
        for (const offset of offsets.split(",")) frames.set(Number.parseFloat(offset), declarations);
    }
    assert.deepEqual([...frames.keys()].sort((a, b) => a - b), [0, 25, 75, 100]);
    assert.equal(frames.get(0).rotate, "0deg");
    assert.equal(frames.get(100).rotate, "0deg");
    assert.equal(frames.get(25).rotate, "var(--icon-wiggle-angle, 6deg)");
    assert.equal(frames.get(75).rotate, "calc(-1 * var(--icon-wiggle-angle, 6deg))");
    assert.equal(frames.get(25)["animation-timing-function"] ?? "ease-in-out", "ease-in-out");
    const curve = offset => {
        const value = frames.get(offset)["animation-timing-function"] ?? "";
        assert.match(value, /^cubic-bezier\([^)]+\)$/);
        return value.slice(value.indexOf("(") + 1, -1).split(",").map(Number);
    };
    // De Casteljau split of ease-in-out (.42, 0, .58, 1) at its midpoint:
    // equal-time quarters meet at nonzero velocity, with zero velocity at extrema.
    assert.deepEqual(curve(0), [0.29, 0.5, 0.58, 1]);
    assert.deepEqual(curve(75), [0.42, 0, 0.71, 0.5]);
});

test("wiggle resets at idle and activates only on native press or fine-pointer hover without reduced motion", () => {
    const css = readFileSync(new URL("../assets/css/style.css", import.meta.url), "utf8");
    assert.match(css, /@media \(prefers-reduced-motion: no-preference\)\s*\{\s*\.icon-wiggle:active,\s*\.icon-control:active \.icon-wiggle\s*\{\s*animation-name: icon-wiggle;\s*\}\s*\}/);
    assert.match(css, /@media \(hover: hover\) and \(pointer: fine\) and \(prefers-reduced-motion: no-preference\)\s*\{\s*\.icon-wiggle:hover,\s*\.icon-control:hover \.icon-wiggle\s*\{\s*animation-name: icon-wiggle;\s*\}\s*\}/);
    assert.equal(css.match(/animation-name: icon-wiggle;/g)?.length, 2,
        "No persistent selection, focus, or ungated hover may start wiggle");
    assert.doesNotMatch(css, /icon-wiggle[^{]*\{[^}]*animation-play-state:/);
    assert.match(css, /@media \(prefers-reduced-motion: reduce\)\s*\{[\s\S]*?\.icon-wiggle\s*\{\s*animation: none;\s*rotate: none;\s*\}/);
    // Existing growth suppression and independent scale are covered above.
});

test("only the two decorative random-reader link icons wiggle; arrow circles keep spinning", () => {
    for (const kind of ["haiku", "story"]) {
        const markup = readFileSync(new URL(`../content/${kind}/_random.md`, import.meta.url), "utf8");
        assert.match(markup, new RegExp(`<a id="${kind}-link" class="icon-control hero-control" hidden>\\s*<span class="control-icon icon-link icon-wiggle" aria-hidden="true"></span>\\s*<span>Link to this ${kind}</span>\\s*</a>`));
        assert.equal(markup.match(/\bicon-wiggle\b/g)?.length, 1);
        assert.equal(markup.match(/class="control-icon icon-arrowcircle icon-spin"/g)?.length, 1);
    }
    for (const path of ["../index.md", "../_layouts/default.html", "../haiku.md", "../story.md"]) {
        assert.doesNotMatch(readFileSync(new URL(path, import.meta.url), "utf8"), /icon-wiggle/);
    }
});
