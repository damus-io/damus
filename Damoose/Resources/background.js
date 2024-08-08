browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    switch (message.kind) {
        case 'approve':
            return browser.runtime.sendNativeMessage("damoose", message.payload)

        case 'deny':
            return Promise.resolve()
    }
});




