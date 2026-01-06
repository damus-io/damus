// Content script - runs in isolated world
// Bridges between injected.js (page context) and background.js (extension context)

(function() {
    'use strict';

    // Inject the window.nostr script into page context
    const script = document.createElement('script');
    script.src = browser.runtime.getURL('injected.js');
    script.onload = function() { this.remove(); };
    (document.head || document.documentElement).appendChild(script);

    // Listen for requests from injected script
    window.addEventListener('DAMUS_REQUEST', async (e) => {
        const { id, method, params } = e.detail;

        try {
            // Forward to background script which talks to native handler
            const result = await browser.runtime.sendMessage({
                type: 'nostr',
                method,
                params
            });

            // Send response back to injected script
            window.dispatchEvent(new CustomEvent('DAMUS_RESPONSE', {
                detail: { id, result }
            }));
        } catch (error) {
            window.dispatchEvent(new CustomEvent('DAMUS_RESPONSE', {
                detail: { id, error: error.message }
            }));
        }
    });
})();
