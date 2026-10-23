/* Fetch one published haiku into the current shell without navigating. */
(async () => {
    const host = document.getElementById("haiku-content");
    const status = document.getElementById("haiku-status");
    status.hidden = false;
    status.textContent = "Loading a haiku…";

    try {
        // Generated URLs are the only selection input; never fetch another origin.
        const choices = JSON.parse(document.getElementById("haiku-targets").textContent);
        if (choices.length === 0) {
            status.textContent = "No published haiku are available yet.";
            return;
        }
        const index = Math.floor(Math.random() * choices.length);
        const target = new URL(choices[index], window.location.href);
        if (target.origin !== window.location.origin ||
            !["http:", "https:"].includes(target.protocol) ||
            target.pathname === window.location.pathname) {
            throw new Error("Unexpected haiku URL");
        }

        // Read only the selected generated page, not its navigation or theme state.
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
        // Keep failures visible and announced rather than leaving a loading message.
        host.replaceChildren();
        status.textContent = "Unable to load a haiku. Please reload the page to try again.";
    }
})();
