
let requests = {}
var host

window.addEventListener('message', message => {
    const { kind, payload } = message.data;
    if (message.data.host)
        host = message.data.host

    if (kind === 'requests') {
        // payload IS the requests object directly from content.js
        requests = Object.assign({}, requests, payload)
    } else if (kind === 'request') {
        requests[payload.reqId] = payload
    }

    update_view(host, requests)
});

function summarize_requests(rs) {
    let grouped = {}
    for (const key of Object.keys(rs)) {
        const {reqId, kind, payload} = rs[key]
        if (grouped[kind] == null) {
            grouped[kind] = []
        }

        grouped[kind].push({reqId, payload})
    }

    return grouped
}

function update_view(host, rs) {
    const reqs = document.getElementById("requests")
    const groups = summarize_requests(rs)

    // Clear existing content safely
    reqs.textContent = ''

    // Create elements using DOM APIs to prevent XSS
    const pre = document.createElement('pre')
    pre.textContent = host
    reqs.appendChild(pre)

    reqs.appendChild(document.createTextNode(' is requesting:'))

    const ul = document.createElement('ul')
    for (const kind of Object.keys(groups)) {
        const li = document.createElement('li')
        const num = groups[kind].length > 1 ? ` x${groups[kind].length}` : ''
        li.textContent = kind + num
        ul.appendChild(li)
    }
    reqs.appendChild(ul)

    const label = document.createElement('label')
    const checkbox = document.createElement('input')
    checkbox.type = 'checkbox'
    checkbox.id = 'remember'
    label.appendChild(checkbox)
    label.appendChild(document.createTextNode(' Remember this permission'))
    reqs.appendChild(label)

    const buttonDiv = document.createElement('div')
    buttonDiv.style.marginTop = '10px'

    const approveBtn = document.createElement('button')
    approveBtn.id = 'approve'
    approveBtn.textContent = 'Approve'
    approveBtn.addEventListener('click', approve)

    const denyBtn = document.createElement('button')
    denyBtn.id = 'deny'
    denyBtn.textContent = 'Deny'
    denyBtn.addEventListener('click', deny)

    buttonDiv.appendChild(approveBtn)
    buttonDiv.appendChild(denyBtn)
    reqs.appendChild(buttonDiv)
}

function act(msgKind) {
    const remember = document.getElementById("remember")?.checked ?? false
    for (const reqId of Object.keys(requests)) {
        const payload = requests[reqId]
        // Include remember flag and origin for permission storage
        const message = {
            kind: msgKind,
            reqId,
            payload,
            remember,
            origin: host
        }
        window.parent.postMessage(message, '*')
        delete requests[reqId]
    }
}

function approve() {
    act("approve")
}

function deny() {
    act("deny")
}

// let the page know the popup iframe is ready to receive nip07 requests for
// approval/disapproval
function popup_initialized() {
    window.parent.postMessage({ kind: "popup_initialized" }, '*');
}

function resolve_request(reqId, kind, payload) {
    window.parent.postMessage({ kind, reqId, payload }, '*');
}

popup_initialized()



