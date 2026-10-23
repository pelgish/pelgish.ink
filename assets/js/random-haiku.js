/* Choose from generated URL data without adding a history entry or visible UI. */
(() => {
    const choices = JSON.parse(document.getElementById("haiku-targets").textContent);
    if (choices.length === 0) return;

    const index = Math.floor(Math.random() * choices.length);
    window.location.replace(choices[index]);
})();
