browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    switch (message.kind) {
        case 'approve':
            return browser.runtime.sendNativeMessage("damoose", message.payload)

        case 'deny':
            return Promise.resolve()
    }
});


function setup_highlighter() {
    browser.contextMenus.create {
        id: "damoose-highlighter",
        title: browser.i18n.getMessage("menuHighlight"),
        contexts: ["selection", "image", "link"],
      },
      handle_menu_item_click
    );

    function handle_menu_item_click(event) {
        let value;
        let { selectionText, srcUrl, mediaType, linkUrl, pageUrl } = event.userInfo;

        if (mediaType === 'image') {
            value = srcUrl;
        } else {
            value = linkUrl || selectionText;
        }

        browser.runtime.sendNativeMessage("damoose", {
            kind: "highlight",
            payload: { mediaType, value, selectionText, pageUrl }
        })
    }
}

setup_highlighter()
