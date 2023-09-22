
import * as nostr from './nostr'

export function go(): i32 {
	let subid = "sidebar_trending"
	let relay = 'wss://cache0.primal.net/cache17'
	var done: i32 = 0
	var events: i32 = 0

	nostr.pool_add_relay(relay)
	nostr.pool_send_to(`["REQ","${subid}",{"cache":["explore_global_trending_24h"]}]`, relay)

	while (!done) {
		var ev = nostr.event_await(subid)
		let type = nostr.event_get_type(ev)
		switch (type) {
		case nostr.EventType.OK:
			nostr.log("ok")
			break
		case nostr.EventType.NOTE:
			events++
			let note = nostr.event_get_note(ev)
			let kind = nostr.note_get_kind(note)
			nostr.log(`type:${type} #${events} note, kind:${kind}`)
			break
		case nostr.EventType.EOSE:
			nostr.log("eose, got " + events.toString() + " events")
			done = true
			break
		default:
			nostr.log("got event type " + type.toString())
		}
	}
	
	return events
}

go()
