// Background script - extension context
// Receives messages from content scripts and forwards to native handler

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type !== 'nostr') {
        return false;
    }

    // Forward to native handler
    handleNostrRequest(message.method, message.params)
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

    if (response.error) {
        throw new Error(response.error);
    }

    return response.result;
}
