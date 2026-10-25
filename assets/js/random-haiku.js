/* Shared haiku/story reader: import published writing without navigating. */
(async () => {
    const host = document.getElementById("haiku-content") || document.getElementById("story-content");
    const kind = host.dataset?.kind === "story" ? "story" : "haiku";
    const style = kind === "story" ? "prose" : "poetry";
    const plural = kind === "story" ? "stories" : "haiku";
    const status = document.getElementById(`${kind}-status`);
    const button = document.getElementById(`${kind}-another`);
    const link = document.getElementById(`${kind}-link`);
    // Each page visit owns its bag; only successfully displayed writing is removed.
    let bag = [];
    let previous;
    let choices;
    try {
        choices = JSON.parse(document.getElementById(`${kind}-targets`).textContent);
        if (!Array.isArray(choices)) throw new Error("Unexpected writing list");
    } catch {
        status.hidden = false;
        status.textContent = `Unable to read the ${kind} list. Please reload the page to try again.`;
        return;
    }

    // Serialize requests so a slow response cannot overwrite a later selection.
    async function loadWriting() {
        if (button.disabled) return;
        button.disabled = true;
        status.hidden = false;
        status.textContent = `Loading a ${kind}…`;
        try {
            if (choices.length === 0) {
                status.textContent = `No published ${plural} are available yet.`;
                return;
            }
            // Fisher-Yates visits every eligible item once before refilling.
            if (bag.length === 0) {
                bag = [...choices];
                for (let i = bag.length - 1; i > 0; i--) {
                    const j = Math.floor(Math.random() * (i + 1));
                    [bag[i], bag[j]] = [bag[j], bag[i]];
                }
                // The next item is at the end; avoid repeating across cycle boundaries.
                const last = bag.length - 1;
                if (bag.length > 1 && bag[last] === previous) {
                    [bag[0], bag[last]] = [bag[last], bag[0]];
                }
            }
            // Generated URLs are the only selection input; never fetch another origin.
            const selection = bag[bag.length - 1];
            const target = new URL(selection, window.location.href);
            if (target.origin !== window.location.origin ||
                !["http:", "https:"].includes(target.protocol) ||
                target.pathname === window.location.pathname) {
                throw new Error("Unexpected writing URL");
            }

            // Import only the writing, not the fetched page's shell or theme state.
            const response = await fetch(target.href, { mode: "same-origin", redirect: "error" });
            if (!response.ok) throw new Error(`Writing request failed (${response.status})`);
            const page = new DOMParser().parseFromString(await response.text(), "text/html");
            const article = page.querySelector(`article.writing.${style}`);
            if (!article?.querySelector(".writing-body")) {
                throw new Error("Writing is missing");
            }
            host.replaceChildren(document.importNode(article, true));
            link.href = target.href;
            link.hidden = false;
            previous = selection;
            bag.pop();
            status.textContent = "";
            status.hidden = true;
        } catch {
            // Leave the latest writing intact while announcing a recoverable failure.
            status.textContent = `Unable to load a ${kind}. Please try the Get a new ${kind} button again.`;
        } finally {
            button.disabled = false;
        }
    }

    button.addEventListener("click", loadWriting);
    button.hidden = false;
    await loadWriting();
})();
