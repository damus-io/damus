// Background script - extension context
// Receives messages from content scripts and forwards to native handler

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type !== 'nostr') {
        return false;
    }

    // Add origin to params for signEvent requests
    const params = { ...message.params };
    if (message.method === 'signEvent' && sender.tab?.url) {
        try {
            const url = new URL(sender.tab.url);
            params.origin = url.hostname;
        } catch (e) {
            params.origin = 'unknown';
        }
    }

    // Forward to native handler
    handleNostrRequest(message.method, params)
        .then(result => sendResponse(result))
        .catch(error => sendResponse({ error: error.message }));

    // Return true to indicate async response
    return true;
});

async function handleNostrRequest(method, params) {
    // Send to native Swift handler via Safari's native messaging
    const response = await browser.runtime.sendNativeMessage('application.id', {
        method,
        params
    });

    // Check if native handler returned an action
    if (response.action === 'openUrl') {
        return handleOpenUrlAction(response);
    }

    if (response.error) {
        throw new Error(response.error);
    }

    return response.result;
}

// Handle openUrl action - opens Damus app and polls for result
async function handleOpenUrlAction(response) {
    const { url, requestId } = response;

    if (!url || !requestId) {
        throw new Error('Invalid openUrl response');
    }

    // Open the nostrsigner:// URL to switch to Damus
    // Note: This may be blocked by Safari. If so, we return the URL for the page to open.
    try {
        // Try to open via a new tab/window
        await browser.tabs.create({ url, active: true });
    } catch (e) {
        // If we can't open directly, return instruction for content script
        return {
            _damusAction: 'openUrl',
            url,
            requestId
        };
    }

    // Poll for result
    return await pollForResult(requestId);
}

// Polls the native handler for a signing result
async function pollForResult(requestId, maxAttempts = 300, intervalMs = 1000) {
    for (let i = 0; i < maxAttempts; i++) {
        await sleep(intervalMs);

        try {
            const response = await browser.runtime.sendNativeMessage('application.id', {
                method: 'checkResult',
                params: { requestId }
            });

            if (response.pending) {
                // Not ready yet, continue polling
                continue;
            }

            if (response.error) {
                throw new Error(response.error);
            }

            return response.result;
        } catch (e) {
            // Native messaging error, might be transient
            console.error('Poll error:', e);
        }
    }

    throw new Error('Signing timed out - please try again');
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
