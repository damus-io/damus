// Content script - runs in isolated world
// Bridges between injected.js (page context) and background.js (extension context)

(function() {
    'use strict';

    // Inject the window.nostr script into page context
    const script = document.createElement('script');
    script.src = browser.runtime.getURL('injected.js');
    script.onload = function() { this.remove(); };
    (document.head || document.documentElement).appendChild(script);

    // Track pending polls for when user returns from Damus
    const pendingPolls = new Map();

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

    // Listen for poll start requests (when page opens Damus URL)
    window.addEventListener('DAMUS_START_POLL', (e) => {
        const { id, requestId } = e.detail;
        pendingPolls.set(requestId, id);
        // Store in sessionStorage so poll survives page navigation
        try {
            const stored = JSON.parse(sessionStorage.getItem('damus_pending_polls') || '{}');
            stored[requestId] = id;
            sessionStorage.setItem('damus_pending_polls', JSON.stringify(stored));
        } catch (e) {
            // sessionStorage may not be available
        }
    });

    // When page becomes visible again (user returned from Damus), check for results
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') {
            checkPendingPolls();
        }
    });

    // Also check on page load/focus in case user returned
    window.addEventListener('focus', checkPendingPolls);
    window.addEventListener('pageshow', checkPendingPolls);

    // Check for any pending polls on load
    setTimeout(checkPendingPolls, 100);

    async function checkPendingPolls() {
        // Restore pending polls from sessionStorage
        try {
            const stored = JSON.parse(sessionStorage.getItem('damus_pending_polls') || '{}');
            for (const [requestId, id] of Object.entries(stored)) {
                if (!pendingPolls.has(requestId)) {
                    pendingPolls.set(requestId, id);
                }
            }
        } catch (e) {
            // sessionStorage may not be available
        }

        if (pendingPolls.size === 0) return;

        // Check each pending poll
        for (const [requestId, id] of pendingPolls.entries()) {
            try {
                const response = await browser.runtime.sendMessage({
                    type: 'nostr',
                    method: 'checkResult',
                    params: { requestId }
                });

                if (response.pending) {
                    // Not ready yet, keep polling
                    continue;
                }

                // Got a result, remove from pending
                pendingPolls.delete(requestId);
                try {
                    const stored = JSON.parse(sessionStorage.getItem('damus_pending_polls') || '{}');
                    delete stored[requestId];
                    sessionStorage.setItem('damus_pending_polls', JSON.stringify(stored));
                } catch (e) {}

                // Send result to injected script
                if (response.error) {
                    window.dispatchEvent(new CustomEvent('DAMUS_POLL_RESULT', {
                        detail: { id, error: response.error }
                    }));
                } else {
                    window.dispatchEvent(new CustomEvent('DAMUS_POLL_RESULT', {
                        detail: { id, result: response.result }
                    }));
                }
            } catch (error) {
                console.error('Poll check error:', error);
            }
        }

        // If there are still pending polls, schedule another check
        if (pendingPolls.size > 0) {
            setTimeout(checkPendingPolls, 1000);
        }
    }
})();
