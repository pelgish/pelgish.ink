/* Initialize appearance before paint, then enhance the site-wide toggle. */
(() => {
    const root = document.documentElement;
    const storageKey = "pelgish-appearance";
    const system = window.matchMedia("(prefers-color-scheme: dark)");
    let explicitAppearance = root.dataset.appearance;

    // Unavailable or full browser storage must not disable the reading control.
    function isStorageFailure(error) {
        return error instanceof DOMException &&
            (error.name === "SecurityError" || error.name === "QuotaExceededError");
    }

    // A remembered user choice takes precedence over page appearance hints.
    try {
        const saved = window.localStorage.getItem(storageKey);
        if (saved === "light" || saved === "dark") {
            explicitAppearance = saved;
        }
    } catch (error) {
        if (!isStorageFailure(error)) throw error;
    }

    // Update the root and accessible next-action label together.
    function applyAppearance() {
        const appearance = explicitAppearance || (system.matches ? "dark" : "light");
        root.dataset.appearance = appearance;
        const button = document.getElementById("appearance-toggle");
        if (button) {
            const nextAppearance = appearance === "dark" ? "light" : "dark";
            const label = `Switch to ${nextAppearance} mode (currently ${appearance} mode)`;
            button.setAttribute("aria-label", label);
            button.title = label;
        }
    }

    applyAppearance();
    system.addEventListener("change", applyAppearance);

    // Keep the control hidden until its click behavior is ready.
    document.addEventListener("DOMContentLoaded", () => {
        // Directory hosts may add a slash; normalize only the current canonical path.
        // Replacing history makes no request and keeps query/hash and baseurl intact.
        const canonicalLink = document.querySelector('link[rel="canonical"]');
        if (canonicalLink) {
            const canonical = new URL(canonicalLink.href);
            const location = window.location;
            if (canonical.origin === location.origin && location.pathname !== "/" &&
                location.pathname.endsWith("/") &&
                location.pathname.replace(/\/+$/, "") === canonical.pathname) {
                window.history.replaceState(window.history.state, "",
                    canonical.pathname + location.search + location.hash);
            }
        }

        const button = document.getElementById("appearance-toggle");
        if (!button) return;
        button.addEventListener("click", () => {
            explicitAppearance = root.dataset.appearance === "dark" ? "light" : "dark";
            applyAppearance();
            try {
                window.localStorage.setItem(storageKey, explicitAppearance);
            } catch (error) {
                if (!isStorageFailure(error)) throw error;
            }
        });
        applyAppearance();
        button.hidden = false;
    });
})();
