/* Fetch published haiku into the current shell without navigating. */
(async () => {
    const host = document.getElementById("haiku-content");
    const status = document.getElementById("haiku-status");
    const button = document.getElementById("haiku-another");
    let choices;
    try {
        choices = JSON.parse(document.getElementById("haiku-targets").textContent);
        if (!Array.isArray(choices)) throw new Error("Unexpected haiku list");
    } catch {
        status.hidden = false;
        status.textContent = "Unable to read the haiku list. Please reload the page to try again.";
        return;
    }

    // Serialize requests so a slow response cannot overwrite a later selection.
    async function loadHaiku() {
        if (button.disabled) return;
        button.disabled = true;
        status.hidden = false;
        status.textContent = "Loading a haiku…";
        try {
            if (choices.length === 0) {
                status.textContent = "No published haiku are available yet.";
                return;
            }
            // Generated URLs are the only selection input; never fetch another origin.
            const index = Math.floor(Math.random() * choices.length);
            const target = new URL(choices[index], window.location.href);
            if (target.origin !== window.location.origin ||
                !["http:", "https:"].includes(target.protocol) ||
                target.pathname === window.location.pathname) {
                throw new Error("Unexpected haiku URL");
            }

            // Import only the writing, not the fetched page's shell or theme state.
            const response = await fetch(target.href, { mode: "same-origin", redirect: "error" });
            if (!response.ok) throw new Error(`Haiku request failed (${response.status})`);
            const page = new DOMParser().parseFromString(await response.text(), "text/html");
            const article = page.querySelector("article.writing.poetry");
            if (!article?.querySelector(".writing-body")) {
                throw new Error("Haiku writing is missing");
            }
            host.replaceChildren(document.importNode(article, true));
            status.textContent = "";
            status.hidden = true;
        } catch {
            // Leave the latest writing intact while announcing a recoverable failure.
            status.textContent = "Unable to load a haiku. Please try the Get a new haiku button again.";
        } finally {
            button.disabled = false;
        }
    }

    button.addEventListener("click", loadHaiku);
    button.hidden = false;
    await loadHaiku();
})();
