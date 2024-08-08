
let requests = {}
var host

window.addEventListener('message', message => {
    const { kind, payload } = message.data;
    if (message.data.host)
        host = message.data.host

    if (kind === 'requests') {
        requests = Object.assign({}, requests, payload.requests)
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

function render_request_groups(grp) {
    return Object.keys(grp).map(k => {
        let num = grp[k].length > 1 ? ` x${grp[k].length}` : ""
        return `<li>${k}${num}</li>`
    }).join("\n")
}

function update_view(host, rs) {
    const reqs = document.getElementById("requests")
    const groups = summarize_requests(rs)
    const rendered_groups = render_request_groups(groups)

    reqs.innerHTML = `
    <pre>${host}</pre> is requesting:
    <ul>
      ${rendered_groups}
    </ul>
    <button id="approve">Approve</button>
    <button id="deny">Deny</button>
    `

    document.getElementById("approve").addEventListener("click", approve)
    document.getElementById("deny").addEventListener("click", deny)
}

function act(kind) {
    for (const reqId of Object.keys(requests)) {
        const payload = requests[reqId]
        window.parent.postMessage({kind, reqId, payload}, '*')
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



